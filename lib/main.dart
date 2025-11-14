import 'dart:async' as dart_async;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:path_provider/path_provider.dart';
import 'core/models/coord.dart';
import 'core/models/tile_state.dart';
import 'core/models/world.dart' as core_models;
import 'core/storage/storage.dart';
import 'core/rules/rules_engine.dart';

void main() {
  runApp(const MinesweeperApp());
}

class MinesweeperApp extends StatefulWidget {
  const MinesweeperApp({super.key});

  @override
  State<MinesweeperApp> createState() => _MinesweeperAppState();
}

class _MinesweeperAppState extends State<MinesweeperApp> with WidgetsBindingObserver {
  MinesweeperGame? _game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    _updateGameBrightness();
  }

  void _updateGameBrightness() {
    if (_game != null) {
      final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      _game!.updateBrightness(brightness);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_game == null) {
      _game = MinesweeperGame();
      // Update brightness after game is created
      Future.microtask(() => _updateGameBrightness());
    }
    return GameWidget<MinesweeperGame>.controlled(
      gameFactory: () => _game!,
    );
  }
}

class MinesweeperGame extends FlameGame with ScaleDetector, DoubleTapDetector, LongPressDetector {
  late core_models.World minesweeperWorld;
  late TileStorage storage;
  late RulesEngine rules;
  late CameraComponent cameraComponent;

  double _startZoom = 1.0;
  final double _tileSize = 32.0;

  // Track tiles we've rendered
  final Map<Coord, TileComponent> _tileComponents = {};

  // Optimization: track last camera state
  Vector2 _lastCameraPos = Vector2.zero();
  double _lastZoom = 1.0;

  // Save file path for local storage
  String? _saveFilePath;
  dart_async.Timer? _autoSaveTimer;

  // Theme brightness
  Brightness brightness = Brightness.light;
  
  // Timer update tracking
  static const Duration _chunkTimeoutDuration = Duration(minutes: 5);
  double _timeSinceLastTimerUpdate = 0;

  @override
  Color backgroundColor() {
    return brightness == Brightness.dark 
        ? const Color(0xFF1A1A1A)  // Dark background
        : const Color(0xFF2E7D32);  // Light mode green background
  }

  @override
  Future<void> onLoad() async {
    // Initialize brightness from platform
    brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    
    // Initialize storage first
    storage = TileStorage();

    // Try to load from previously selected directory
    await _loadWorld();

    // Initialize rules engine
    rules = RulesEngine(minesweeperWorld, storage);

    // Set up camera with world
    final gameWorld = World();
    cameraComponent = CameraComponent(world: gameWorld)
      ..viewfinder.zoom = 1.0
      ..viewfinder.position = Vector2.zero();
    add(gameWorld);
    add(cameraComponent);

    // Render initial visible tiles
    _updateVisibleTiles();

    // Set up auto-save every 30 seconds
    _autoSaveTimer = dart_async.Timer.periodic(const Duration(seconds: 30), (_) => _saveWorld());
  }

  void updateBrightness(Brightness newBrightness) {
    if (brightness != newBrightness) {
      brightness = newBrightness;
      _updateVisibleTiles();
    }
  }

  core_models.World _createDefaultWorld() {
    return core_models.World(
      seed: 'default',
      chunkSize: 16,
      minesPerChunk: 40,
      name: 'Default World',
      formatVersion: '1.0',
    );
  }

  Future<void> _loadWorld() async {
    // Get app's local storage directory
    final appDir = await getApplicationDocumentsDirectory();
    final worldsDir = Directory('${appDir.path}/worlds');
    if (!await worldsDir.exists()) {
      await worldsDir.create(recursive: true);
    }

    _saveFilePath = '${worldsDir.path}/test_world.json';

    // Try to load existing file
    final file = File(_saveFilePath!);
    if (await file.exists()) {
      final loadedWorld = await storage.loadFromFile(_saveFilePath!);
      if (loadedWorld != null) {
        minesweeperWorld = loadedWorld;
        print('Loaded world from: $_saveFilePath');
        return;
      }
    }

    // Create new world if no save exists
    minesweeperWorld = _createDefaultWorld();
    print('Created new world at: $_saveFilePath');
  }

  Future<void> _saveWorld() async {
    if (_saveFilePath != null) {
      try {
        await storage.saveToFile(_saveFilePath!, world: minesweeperWorld);
        print('Saved ${storage.count} tiles to: $_saveFilePath');
      } catch (e) {
        print('Error saving world: $e');
      }
    }
  }

  @override
  void onRemove() {
    _autoSaveTimer?.cancel();
    // Attempt final save (fire and forget as we're closing)
    _saveWorld();
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Only update if camera moved significantly
    final camera = cameraComponent.viewfinder;
    if ((camera.position - _lastCameraPos).length > _tileSize * 2 ||
        (camera.zoom - _lastZoom).abs() > 0.1) {
      _updateVisibleTiles();
      _lastCameraPos = camera.position.clone();
      _lastZoom = camera.zoom;
    }
    
    // Update timer display every second if there are active timeouts
    _timeSinceLastTimerUpdate += dt;
    if (_timeSinceLastTimerUpdate >= 1.0) {
      _timeSinceLastTimerUpdate = 0;
      
      // Convert expired exploded tiles to flagged
      _convertExpiredExplosionsToFlags();
      
      // Check if any visible tiles have active timeouts
      for (final tile in _tileComponents.values) {
        if (getChunkTimeoutInfo(tile.coord).$1) {
          _updateVisibleTiles();
          break;
        }
      }
    }
  }

  // Convert exploded tiles to flagged after timeout expires
  void _convertExpiredExplosionsToFlags() {
    final now = DateTime.now();
    final tiles = storage.snapshot();
    
    for (final entry in tiles.entries) {
      final coord = entry.key;
      final state = entry.value;
      
      if (state.exploded && state.openedAt != null) {
        final unlockTime = state.openedAt!.add(_chunkTimeoutDuration);
        if (now.isAfter(unlockTime)) {
          // Convert to flagged and remove exploded state
          final newState = TileState(
            flag: TileFlag.flagged,
            exploded: false,
            openedAt: null,
          );
          storage.updateTileState(coord, newState);
        }
      }
    }
  }

  void _updateVisibleTiles() {
    final camera = cameraComponent.viewfinder;
    final zoom = camera.zoom;
    final cameraPos = camera.position;

    // Calculate visible area in tile coordinates
    final screenWidth = size.x / zoom;
    final screenHeight = size.y / zoom;

    final minX = ((cameraPos.x - screenWidth / 2) / _tileSize).floor() - 1;
    final maxX = ((cameraPos.x + screenWidth / 2) / _tileSize).ceil() + 1;
    final minY = ((cameraPos.y - screenHeight / 2) / _tileSize).floor() - 1;
    final maxY = ((cameraPos.y + screenHeight / 2) / _tileSize).ceil() + 1;

    // Add tiles that are visible but not yet rendered
    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        final coord = Coord(x, y);
        if (!_tileComponents.containsKey(coord)) {
          final tile = TileComponent(
            coord: coord,
            tileSize: _tileSize,
            game: this,
          );
          _tileComponents[coord] = tile;
          cameraComponent.world?.add(tile);
        }
      }
    }

    // Update all rendered tiles
    for (final tile in _tileComponents.values) {
      tile.updateTileState();
    }
  }

  // Scale/Pan gestures
  @override
  void onScaleStart(ScaleStartInfo info) {
    _startZoom = cameraComponent.viewfinder.zoom;
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    final scale = info.scale.global;

    if (!scale.isIdentity()) {
      // Zoom
      cameraComponent.viewfinder.zoom = (_startZoom * scale.y).clamp(0.1, 5.0);
    } else {
      // Pan
      final delta = info.delta.global / cameraComponent.viewfinder.zoom;
      cameraComponent.viewfinder.position -= delta;
    }
  }

  // Double tap to open tile
  @override
  void onDoubleTapDown(TapDownInfo info) {
    final worldPos = cameraComponent.viewfinder.position +
        (info.eventPosition.widget - size / 2) / cameraComponent.viewfinder.zoom;
    final coord = Coord(
      (worldPos.x / _tileSize).floor(),
      (worldPos.y / _tileSize).floor(),
    );

    rules.openTile(coord);
    _updateVisibleTiles();
    _saveWorld(); // Save after tile interaction
  }

  // Long press to flag tile
  @override
  void onLongPressStart(LongPressStartInfo info) {
    final worldPos = cameraComponent.viewfinder.position +
        (info.eventPosition.widget - size / 2) / cameraComponent.viewfinder.zoom;
    final coord = Coord(
      (worldPos.x / _tileSize).floor(),
      (worldPos.y / _tileSize).floor(),
    );

    rules.flagTile(coord);
    _updateVisibleTiles();
    _saveWorld(); // Save after tile interaction
  }

  // Check if chunk has recent explosion and get time remaining
  (bool, Duration?) getChunkTimeoutInfo(Coord coord) {
    final chunkCoord = coord.toChunk(minesweeperWorld.chunkSize);
    final now = DateTime.now();
    final cutoff = now.subtract(_chunkTimeoutDuration);

    final chunkSize = minesweeperWorld.chunkSize;
    final startX = chunkCoord.chunkX * chunkSize;
    final startY = chunkCoord.chunkY * chunkSize;

    DateTime? mostRecentExplosion;

    for (int ly = 0; ly < chunkSize; ly++) {
      for (int lx = 0; lx < chunkSize; lx++) {
        final c = Coord(startX + lx, startY + ly);
        final state = storage.get(c);
        if (state.exploded && state.openedAt != null && state.openedAt!.isAfter(cutoff)) {
          if (mostRecentExplosion == null || state.openedAt!.isAfter(mostRecentExplosion)) {
            mostRecentExplosion = state.openedAt;
          }
        }
      }
    }

    if (mostRecentExplosion != null) {
      final unlockTime = mostRecentExplosion.add(_chunkTimeoutDuration);
      final remaining = unlockTime.difference(now);
      return (true, remaining);
    }
    return (false, null);
  }

  bool isChunkTimedOut(Coord coord) {
    return getChunkTimeoutInfo(coord).$1;
  }
}

class TileComponent extends PositionComponent {
  final Coord coord;
  final double tileSize;
  final MinesweeperGame game;

  TileComponent({
    required this.coord,
    required this.tileSize,
    required this.game,
  }) {
    position = Vector2(coord.x * tileSize, coord.y * tileSize);
    size = Vector2.all(tileSize);
  }

  void updateTileState() {
    // Force redraw by marking as dirty
  }

  @override
  void render(Canvas canvas) {
    final state = game.storage.get(coord);
    final timeoutInfo = game.getChunkTimeoutInfo(coord);
    final isTimedOut = timeoutInfo.$1;
    final timeRemaining = timeoutInfo.$2;
    final isDarkMode = game.brightness == Brightness.dark;

    // Calculate chunk boundaries for drawing chunk borders
    final chunkCoord = coord.toChunk(game.minesweeperWorld.chunkSize);
    final chunkSize = game.minesweeperWorld.chunkSize;
    final chunkStartX = chunkCoord.chunkX * chunkSize;
    final chunkStartY = chunkCoord.chunkY * chunkSize;
    final isLeftEdge = coord.x == chunkStartX;
    final isRightEdge = coord.x == chunkStartX + chunkSize - 1;
    final isTopEdge = coord.y == chunkStartY;
    final isBottomEdge = coord.y == chunkStartY + chunkSize - 1;

    // Draw tile based on state
    final paint = Paint();

    if (state.exploded && !isTimedOut) {
      // Black for exploded (but not during timeout)
      paint.color = Colors.black;
    } else if (state.flag == TileFlag.flagged) {
      // Red for flagged
      paint.color = Colors.red;
    } else if (state.flag == TileFlag.open) {
      // White/light grey for open in light mode, darker in dark mode
      paint.color = isDarkMode ? const Color(0xFF2A2A2A) : Colors.white;
    } else {
      // Closed tiles
      if (isDarkMode) {
        // Dark mode: all closed tiles black
        paint.color = Colors.black;
      } else {
        // Light mode: lighter green checkerboard
        final isDark = (coord.x + coord.y) % 2 == 0;
        paint.color = isDark ? const Color(0xFF66BB6A) : const Color(0xFF81C784);
      }
    }

    // Apply blur effect for timed out chunks (more visible now)
    if (isTimedOut && state.flag == TileFlag.closed) {
      paint.color = paint.color.withAlpha((255 * 0.3).toInt());
    }

    canvas.drawRect(size.toRect(), paint);

    // Draw red dot on exploded tiles during timeout
    if (state.exploded && isTimedOut) {
      final dotPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(tileSize / 2, tileSize / 2),
        tileSize * 0.15,
        dotPaint,
      );
    }

    // Draw glow effect on open tiles
    if (state.flag == TileFlag.open && !state.exploded) {
      final glowPaint = Paint()
        ..color = (isDarkMode ? Colors.grey[800]! : Colors.grey[300]!).withAlpha(128)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      
      canvas.drawCircle(Offset(tileSize / 2, tileSize / 2), tileSize * 0.35, glowPaint);
    }

    // Draw tile borders (only in dark mode for individual tiles)
    if (isDarkMode) {
      final tileBorderPaint = Paint()
        ..color = const Color(0xFF00FF00)  // Green borders in dark mode
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      canvas.drawRect(size.toRect(), tileBorderPaint);
    }

    // Draw chunk borders (thicker, always visible)
    // Make chunks touch on 1/3 of tile width by extending borders
    final chunkBorderWidth = isDarkMode ? 2.5 : 3.5;
    final chunkBorderColor = isDarkMode ? const Color(0xFF9C27B0) : Colors.black;  // Violet in dark, black in light
    final chunkBorderPaint = Paint()
      ..color = chunkBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = chunkBorderWidth
      ..strokeCap = StrokeCap.square;

    final halfBorder = chunkBorderWidth / 2;
    final overlap = tileSize / 3;  // Overlap 1/3 of tile width

    if (isLeftEdge) {
      canvas.drawLine(
        Offset(halfBorder, -overlap),
        Offset(halfBorder, tileSize + overlap),
        chunkBorderPaint,
      );
    }
    if (isRightEdge) {
      canvas.drawLine(
        Offset(tileSize - halfBorder, -overlap),
        Offset(tileSize - halfBorder, tileSize + overlap),
        chunkBorderPaint,
      );
    }
    if (isTopEdge) {
      canvas.drawLine(
        Offset(-overlap, halfBorder),
        Offset(tileSize + overlap, halfBorder),
        chunkBorderPaint,
      );
    }
    if (isBottomEdge) {
      canvas.drawLine(
        Offset(-overlap, tileSize - halfBorder),
        Offset(tileSize + overlap, tileSize - halfBorder),
        chunkBorderPaint,
      );
    }

    // Draw hint number if open and not exploded
    if (state.flag == TileFlag.open && !state.exploded) {
      final hint = game.rules.getHint(coord);
      if (hint > 0) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: hint.toString(),
            style: TextStyle(
              color: _getHintColor(hint, isDarkMode),
              fontSize: tileSize * 0.6,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            (tileSize - textPainter.width) / 2,
            (tileSize - textPainter.height) / 2,
          ),
        );
      }
    }

    // Draw timer on timed-out chunks (centered in the chunk)
    if (isTimedOut && timeRemaining != null) {
      // Only draw on the center tile of the chunk
      final centerTileX = chunkSize ~/ 2;
      final centerTileY = chunkSize ~/ 2;
      final isCenterTile = (coord.x - chunkStartX) == centerTileX && (coord.y - chunkStartY) == centerTileY;
      
      if (isCenterTile) {
        final minutes = timeRemaining.inMinutes;
        final seconds = timeRemaining.inSeconds % 60;
        final timerText = '$minutes:${seconds.toString().padLeft(2, '0')}';
        
        final timerPainter = TextPainter(
          text: TextSpan(
            text: timerText,
            style: TextStyle(
              color: isDarkMode ? Colors.red[300] : Colors.red[700],
              fontSize: tileSize * 1.2,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: Colors.black.withAlpha(200),
                  offset: const Offset(2, 2),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        timerPainter.layout();
        
        // Draw centered on this tile
        timerPainter.paint(
          canvas,
          Offset(
            (tileSize - timerPainter.width) / 2,
            (tileSize - timerPainter.height) / 2,
          ),
        );
      }
    }
  }

  Color _getHintColor(int hint, bool isDarkMode) {
    if (isDarkMode) {
      // Lighter colors for dark mode
      switch (hint) {
        case 1:
          return Colors.lightBlue[300]!;
        case 2:
          return Colors.lightGreen[300]!;
        case 3:
          return Colors.red[300]!;
        case 4:
          return Colors.purple[300]!;
        case 5:
          return Colors.orange[300]!;
        case 6:
          return Colors.cyan[300]!;
        case 7:
          return Colors.grey[300]!;
        case 8:
          return Colors.grey[400]!;
        default:
          return Colors.grey[300]!;
      }
    } else {
      // Original colors for light mode
      switch (hint) {
        case 1:
          return Colors.blue;
        case 2:
          return Colors.green;
        case 3:
          return Colors.red;
        case 4:
          return Colors.purple;
        case 5:
          return Colors.orange;
        case 6:
          return Colors.cyan;
        case 7:
          return Colors.black;
        case 8:
          return Colors.grey;
        default:
          return Colors.black;
      }
    }
  }
}

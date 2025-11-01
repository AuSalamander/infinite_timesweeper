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
  runApp(const GameWidget.controlled(
    gameFactory: MinesweeperGame.new,
  ));
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

  @override
  Color backgroundColor() => const Color(0xFF2E7D32); // Dark green

  @override
  Future<void> onLoad() async {
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

  // Check if chunk has recent explosion
  bool isChunkTimedOut(Coord coord) {
    final chunkCoord = coord.toChunk(minesweeperWorld.chunkSize);
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(minutes: 5));

    final chunkSize = minesweeperWorld.chunkSize;
    final startX = chunkCoord.chunkX * chunkSize;
    final startY = chunkCoord.chunkY * chunkSize;

    for (int ly = 0; ly < chunkSize; ly++) {
      for (int lx = 0; lx < chunkSize; lx++) {
        final c = Coord(startX + lx, startY + ly);
        final state = storage.get(c);
        if (state.exploded && state.openedAt != null && state.openedAt!.isAfter(cutoff)) {
          return true;
        }
      }
    }
    return false;
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
    final isTimedOut = game.isChunkTimedOut(coord);

    // Draw tile based on state
    final paint = Paint();

    if (state.exploded) {
      // Black for exploded
      paint.color = Colors.black;
    } else if (state.flag == TileFlag.flagged) {
      // Red for flagged
      paint.color = Colors.red;
    } else if (state.flag == TileFlag.open) {
      // White for open
      paint.color = Colors.white;
    } else {
      // Closed: checkerboard pattern (dark/light green)
      final isDark = (coord.x + coord.y) % 2 == 0;
      paint.color = isDark ? const Color(0xFF1B5E20) : const Color(0xFF4CAF50);
    }

    // Apply blur effect for timed out chunks
    if (isTimedOut && state.flag == TileFlag.closed) {
      paint.color = paint.color.withAlpha((255 * 0.5).toInt());
    }

    canvas.drawRect(size.toRect(), paint);

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(size.toRect(), borderPaint);

    // Draw hint number if open and not exploded
    if (state.flag == TileFlag.open && !state.exploded) {
      final hint = game.rules.getHint(coord);
      if (hint > 0) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: hint.toString(),
            style: TextStyle(
              color: _getHintColor(hint),
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
  }

  Color _getHintColor(int hint) {
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

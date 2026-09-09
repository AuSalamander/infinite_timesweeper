import 'dart:async' as dart_async;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/input.dart';
import 'package:path_provider/path_provider.dart';
import 'core/models/coord.dart';
import 'core/models/tile_state.dart';
import 'core/models/world.dart' as core_models;
import 'core/storage/storage.dart';
import 'core/rules/rules_engine.dart';
import 'core/perf/frame_stats.dart';

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
    final game = _game!;
    // Note: no MaterialApp in this app, so provide Directionality explicitly
    // for the overlay Text (GameWidget alone never needed it).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
      children: [
        Positioned.fill(
          child: GameWidget<MinesweeperGame>.controlled(
            gameFactory: () => game,
          ),
        ),
        // On-screen perf readout (debug + profile only; game pushes
        // a new string every ~2s, see MinesweeperGame.update).
        // SafeArea keeps it below the Android status bar / notch.
        Positioned(
          top: 0,
          left: 8,
          right: 8,
          child: SafeArea(
            child: IgnorePointer(
              child: ValueListenableBuilder<String>(
                valueListenable: game.perfOverlay,
                builder: (context, text, _) {
                  if (kReleaseMode) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(160),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      text,
                      softWrap: true,
                      maxLines: 3,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}

class MinesweeperGame extends FlameGame with ScaleDetector, TapDetector, LongPressDetector {
  late core_models.World minesweeperWorld;
  late TileStorage storage;
  late RulesEngine rules;
  late CameraComponent cameraComponent;

  double _startZoom = 1.0;
  final double _tileSize = 32.0;
  double get tileSize => _tileSize;

  // Manual double-tap: open only when two consecutive taps hit the same cell.
  // (Flutter's DoubleTapGestureRecognizer allows ~100px slop, which spans
  // several tiles when zoomed out, so we detect the double-tap ourselves
  // via TapDetector.)
  static const Duration _doubleTapTimeout = Duration(milliseconds: 300);
  Coord? _pendingTapCoord;
  DateTime? _pendingTapTime;

  Coord _coordFromWidgetPos(Vector2 widgetPos) {
    final worldPos = cameraComponent.viewfinder.position +
        (widgetPos - size / 2) / cameraComponent.viewfinder.zoom;
    return Coord(
      (worldPos.x / _tileSize).floor(),
      (worldPos.y / _tileSize).floor(),
    );
  }

  // Single batched renderer (replaces per-tile components).
  BoardRenderer? _boardRenderer;

  // Save file path for local storage
  String? _saveFilePath;
  dart_async.Timer? _autoSaveTimer;

  // Theme brightness
  Brightness brightness = Brightness.light;

  // Timer update tracking. _frameNow is refreshed once per update() and
  // shared by the renderer + timeout checks (no DateTime.now per tile).
  static const Duration _chunkTimeoutDuration = Duration(minutes: 5);
  DateTime _frameNow = DateTime.now();
  DateTime get frameNow => _frameNow;
  double _timeSinceLastTimerUpdate = 0;

  // Explosion timestamps per chunk (int keys, no string allocs).
  final Map<int, DateTime> _chunkExplosionTimes = {};
  bool get hasPendingTimeouts => _chunkExplosionTimes.isNotEmpty;

  // Dirty flag for saves
  bool _hasUnsavedChanges = false;

  // Debug+profile perf counters (zero-cost in release, see FrameStats).
  // perfOverlay drives the on-screen readout; updated ~every 2s.
  final FrameStats perf = FrameStats();
  final ValueNotifier<String> perfOverlay =
      ValueNotifier<String>('PERF starting…');
  bool _isLoaded = false;

  static int chunkKey(int chunkX, int chunkY) =>
      ((chunkX & 0xffffffff) << 32) | (chunkY & 0xffffffff);

  // Floor-division chunk of a tile without allocating a Coord.
  static int chunkOf(int tile, int chunkSize) {
    return (tile >= 0) ? tile ~/ chunkSize : -(((-tile - 1) ~/ chunkSize) + 1);
  }

  @override
  Color backgroundColor() {
    return brightness == Brightness.dark
        ? const Color(0xFF1A1A1A) // Dark background
        : const Color(0xFF2E7D32); // Light mode green background
  }

  @override
  Future<void> onLoad() async {
    // Initialize brightness from platform
    brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    _frameNow = DateTime.now();

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

    // One renderer draws every visible tile; no per-tile components.
    _boardRenderer = BoardRenderer(game: this);
    await gameWorld.add(_boardRenderer!);
    _isLoaded = true;

    // Set up auto-save every 30 seconds (only if changes)
    _autoSaveTimer = dart_async.Timer.periodic(const Duration(seconds: 30), (_) {
      if (_hasUnsavedChanges) {
        _saveWorld();
      }
    });
  }

  void updateBrightness(Brightness newBrightness) {
    if (brightness != newBrightness) {
      brightness = newBrightness;
      // Renderer reads brightness live; nothing to rebuild.
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

        // Rebuild chunk explosion cache from loaded data
        _rebuildChunkExplosionCache();
        // Convert already-stale explosions once so the 1s loop can
        // early-out on empty cache afterwards.
        _convertExpiredExplosionsToFlags(forceFullScan: true);
        return;
      }
    }

    // Create new world if no save exists
    minesweeperWorld = _createDefaultWorld();
    print('Created new world at: $_saveFilePath');
  }

  Future<void> _saveWorld() async {
    if (_saveFilePath != null && _hasUnsavedChanges) {
      try {
        await storage.saveToFile(_saveFilePath!, world: minesweeperWorld);
        _hasUnsavedChanges = false;
        print('Saved ${storage.count} tiles to: $_saveFilePath');
      } catch (e) {
        print('Error saving world: $e');
      }
    }
  }

  @override
  void onRemove() {
    _autoSaveTimer?.cancel();
    perfOverlay.dispose();
    // Attempt final save (fire and forget as we're closing)
    _saveWorld();
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Single clock read per frame; renderer + timeout logic reuse it.
    _frameNow = DateTime.now();
    perf.recordFrame(dt);

    // Expire a single pending tap (arms the manual double-tap only briefly).
    if (_pendingTapTime != null &&
        _frameNow.difference(_pendingTapTime!) > _doubleTapTimeout) {
      _pendingTapCoord = null;
      _pendingTapTime = null;
    }

    // 1s throttle for timeout expiry (no per-tile per-frame scans).
    _timeSinceLastTimerUpdate += dt;
    if (_timeSinceLastTimerUpdate >= 1.0) {
      _timeSinceLastTimerUpdate = 0;
      if (hasPendingTimeouts) {
        _pruneExpiredChunkTimes();
        _convertExpiredExplosionsToFlags();
      }
    }

    if (!_isLoaded) return;
    final report = perf.maybeReport(dt,
        storedTiles: storage.count,
        chunkHits: rules.cacheHits,
        chunkMisses: rules.cacheMisses);
    if (report != null && !kReleaseMode) {
      debugPrint(report);
      perfOverlay.value = report;
    }
  }

  void _pruneExpiredChunkTimes() {
    if (_chunkExplosionTimes.isEmpty) return;
    final expired = <int>[];
    for (final entry in _chunkExplosionTimes.entries) {
      if (_frameNow.isAfter(entry.value.add(_chunkTimeoutDuration))) {
        expired.add(entry.key);
      }
    }
    for (final key in expired) {
      _chunkExplosionTimes.remove(key);
    }
  }

  // Convert exploded tiles to flagged after timeout expires.
  // Skipped entirely when no pending timeouts (the common late-game case
  // is thousands of open tiles but zero pending explosions).
  void _convertExpiredExplosionsToFlags({bool forceFullScan = false}) {
    if (!forceFullScan && _chunkExplosionTimes.isEmpty) {
      // Empty cache means nothing pending. (Stale tiles from disk are
      // handled by the forced pass in _loadWorld.)
      return;
    }
    final now = _frameNow;
    final expired = <Coord>[];
    for (final entry in storage.entries) {
      final state = entry.value;
      if (state.exploded && state.openedAt != null) {
        if (now.isAfter(state.openedAt!.add(_chunkTimeoutDuration))) {
          expired.add(entry.key);
        }
      }
    }
    for (final coord in expired) {
      storage.updateTileState(
        coord,
        const TileState(flag: TileFlag.flagged, exploded: false),
      );
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
      // Zoom (no forced limit; renderer handles arbitrary zoom)
      cameraComponent.viewfinder.zoom = (_startZoom * scale.y).clamp(0.1, 5.0);
    } else {
      // Pan
      final delta = info.delta.global / cameraComponent.viewfinder.zoom;
      cameraComponent.viewfinder.position -= delta;
    }
  }

  // Double tap (two consecutive TapDetector taps on the same cell) to open tile.
  @override
  void onTapUp(TapUpInfo info) {
    final coord = _coordFromWidgetPos(info.eventPosition.widget);
    final now = DateTime.now();
    final prevCoord = _pendingTapCoord;
    final prevTime = _pendingTapTime;
    if (prevCoord != null &&
        prevTime != null &&
        prevCoord == coord &&
        now.difference(prevTime) <= _doubleTapTimeout) {
      // Second tap on the same cell: consume and open.
      _pendingTapCoord = null;
      _pendingTapTime = null;
      rules.openTile(coord, onExplosion: _recordChunkExplosion);
      // Renderer reads storage live; no rebuild needed.
      _hasUnsavedChanges = true;
    } else {
      // First tap (or different cell / expired): arm for the next tap.
      _pendingTapCoord = coord;
      _pendingTapTime = now;
    }
  }

  // Long press to flag tile
  @override
  void onLongPressStart(LongPressStartInfo info) {
    final coord = _coordFromWidgetPos(info.eventPosition.widget);

    rules.flagTile(coord);
    _hasUnsavedChanges = true;
  }

  // Check if chunk has recent explosion and get time remaining.
  // Uses the shared _frameNow; never calls DateTime.now() per tile.
  (bool, Duration?) getChunkTimeoutInfo(Coord coord) {
    if (_chunkExplosionTimes.isEmpty) return (false, null);
    final chunkCoord = coord.toChunk(minesweeperWorld.chunkSize);
    final key = chunkKey(chunkCoord.chunkX, chunkCoord.chunkY);

    final explosionTime = _chunkExplosionTimes[key];
    if (explosionTime == null) return (false, null);

    final unlockTime = explosionTime.add(_chunkTimeoutDuration);
    if (_frameNow.isAfter(unlockTime)) {
      _chunkExplosionTimes.remove(key);
      return (false, null);
    }
    return (true, unlockTime.difference(_frameNow));
  }

  // Same as above but without allocating a Coord (renderer hot loop).
  (bool, Duration?) getChunkTimeoutInfoXY(int tileX, int tileY) {
    if (_chunkExplosionTimes.isEmpty) return (false, null);
    final cs = minesweeperWorld.chunkSize;
    return getChunkTimeoutByChunk(
        chunkOf(tileX, cs), chunkOf(tileY, cs));
  }

  // Chunk-level query: no tile state involved, so the lock badge never
  // depends on what the center tile happens to be (open/flagged/etc).
  (bool, Duration?) getChunkTimeoutByChunk(int chunkX, int chunkY) {
    if (_chunkExplosionTimes.isEmpty) return (false, null);
    final key = chunkKey(chunkX, chunkY);
    final explosionTime = _chunkExplosionTimes[key];
    if (explosionTime == null) return (false, null);
    final unlockTime = explosionTime.add(_chunkTimeoutDuration);
    if (_frameNow.isAfter(unlockTime)) {
      _chunkExplosionTimes.remove(key);
      return (false, null);
    }
    return (true, unlockTime.difference(_frameNow));
  }

  // Track explosion in chunk
  void _recordChunkExplosion(Coord coord, DateTime timestamp) {
    final chunkCoord = coord.toChunk(minesweeperWorld.chunkSize);
    final key = chunkKey(chunkCoord.chunkX, chunkCoord.chunkY);

    final existing = _chunkExplosionTimes[key];
    if (existing == null || timestamp.isAfter(existing)) {
      _chunkExplosionTimes[key] = timestamp;
    }
  }

  // Rebuild chunk explosion cache from storage (called on load)
  void _rebuildChunkExplosionCache() {
    _chunkExplosionTimes.clear();
    final now = DateTime.now();
    final cutoff = now.subtract(_chunkTimeoutDuration);

    for (final entry in storage.entries) {
      final state = entry.value;
      if (state.exploded && state.openedAt != null && state.openedAt!.isAfter(cutoff)) {
        _recordChunkExplosion(entry.key, state.openedAt!);
      }
    }
  }

  bool isChunkTimedOut(Coord coord) {
    return getChunkTimeoutInfo(coord).$1;
  }
}

/// Single batched renderer: draws every visible tile in one component.
///
/// Replaces the old one-Component-per-tile approach (which created 60k-250k
/// components when zoomed out). Only hint/timer text is skipped when it would
/// be subpixel (<10px on-screen); tiles, blurred glow, tile borders and the
/// chunk grid are always drawn (visual baseline for measurement).
class BoardRenderer extends Component {
  final MinesweeperGame game;

  BoardRenderer({required this.game});

  // Reused paints: zero per-frame allocation.
  static final Paint _closedLightA = Paint()..color = const Color(0xFF66BB6A);
  static final Paint _closedLightB = Paint()..color = const Color(0xFF81C784);
  static final Paint _closedDark = Paint()..color = Colors.black;
  static final Paint _openLight = Paint()..color = Colors.white;
  static final Paint _openDark = Paint()..color = const Color(0xFF2A2A2A);
  static final Paint _flagged = Paint()..color = Colors.red;
  static final Paint _exploded = Paint()..color = Colors.black;
  static final Paint _timedOutDim = Paint()
    ..color = const Color(0xFF81C784).withAlpha((255 * 0.3).toInt());
  static final Paint _timedOutDimDark = Paint()
    ..color = Colors.black.withAlpha((255 * 0.3).toInt());
  // Glow with original blur (shared static paints: no per-frame alloc,
  // blur raster cost itself is what we will measure in step 1).
  static final Paint _glowLight = Paint()
    ..color = Colors.grey[300]!.withAlpha(128)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
  static final Paint _glowDark = Paint()
    ..color = Colors.grey[800]!.withAlpha(128)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
  static final Paint _redDot = Paint()
    ..color = Colors.red
    ..style = PaintingStyle.fill;
  static final Paint _tileBorderDark = Paint()
    ..color = const Color(0xFF00FF00)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;
  static final Paint _chunkBorderLight = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.5;
  static final Paint _chunkBorderDark = Paint()
    ..color = const Color(0xFF9C27B0)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  static final Paint _chunkBorderLocked = Paint()
    ..color = const Color(0xFFE53935)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0;
  // Big lock badge: dark pill + red outline, identical in both themes so
  // the locked chunk reads instantly.
  static final Paint _lockBadgeBg = Paint()
    ..color = const Color(0xDD111111);
  static final Paint _lockBadgeBorder = Paint()
    ..color = const Color(0xFFE53935)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0;
  static final Paint _lockedChunkShade = Paint()
    ..color = const Color(0x55000000);

  // Cache text painters for hints (immutable per hint value/theme).
  static final Map<String, TextPainter> _textPainterCache = {};
  // Timer text changes once per second: cache per second-value.
  static final Map<String, TextPainter> _timerPainterCache = {};

  static TextPainter _hintPainter(String text, TextStyle style) {
    final key = '$text-${style.color}-${style.fontSize}';
    return _textPainterCache.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  static TextPainter _timerPainter(String text, Color color, double fontSize) {
    final key = '$text-$color-$fontSize';
    return _timerPainterCache.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  @override
  void render(Canvas canvas) {
    final Stopwatch? sw = kReleaseMode ? null : (Stopwatch()..start());
    final viewfinder = game.cameraComponent.viewfinder;
    final zoom = viewfinder.zoom;
    final cameraPos = viewfinder.position;
    final tileSize = game.tileSize;
    final chunkSize = game.minesweeperWorld.chunkSize;
    final isDarkMode = game.brightness == Brightness.dark;

    final screenWidth = game.size.x / zoom;
    final screenHeight = game.size.y / zoom;

    final minX = ((cameraPos.x - screenWidth / 2) / tileSize).floor() - 1;
    final maxX = ((cameraPos.x + screenWidth / 2) / tileSize).ceil() + 1;
    final minY = ((cameraPos.y - screenHeight / 2) / tileSize).floor() - 1;
    final maxY = ((cameraPos.y + screenHeight / 2) / tileSize).ceil() + 1;

    // On-screen tile size drives text detail only. Borders/glow/dots are
    // always drawn (visual baseline); hint + timer text below ~10px
    // on-screen is subpixel and skipped. Chunk grid is always drawn.
    final tileScreen = tileSize * zoom;
    final drawText = tileScreen >= 10.0;

    final hasTimeouts = game.hasPendingTimeouts;
    final chunkBorderPaint = isDarkMode ? _chunkBorderDark : _chunkBorderLight;

    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        // One Coord alloc per visible tile (vs one Component + Set entry +
        // several Paints before). Storage lookup needs it.
        final coord = Coord(x, y);
        final state = game.storage.get(coord);
        final rect = Rect.fromLTWH(x * tileSize, y * tileSize, tileSize, tileSize);

        bool isTimedOut = false;
        if (hasTimeouts &&
            (state.flag == TileFlag.closed || state.exploded)) {
          isTimedOut = game.getChunkTimeoutInfoXY(x, y).$1;
        }

        final Paint paint;
        if (state.exploded && !isTimedOut) {
          paint = _exploded;
        } else if (state.flag == TileFlag.flagged) {
          paint = _flagged;
        } else if (state.flag == TileFlag.open) {
          paint = isDarkMode ? _openDark : _openLight;
        } else {
          if (isDarkMode) {
            paint = isTimedOut ? _timedOutDimDark : _closedDark;
          } else {
            if (isTimedOut) {
              paint = _timedOutDim;
            } else {
              paint = ((x + y) % 2 == 0) ? _closedLightA : _closedLightB;
            }
          }
        }
        canvas.drawRect(rect, paint);

        final cx = x * tileSize + tileSize / 2;
        final cy = y * tileSize + tileSize / 2;

        if (state.exploded && isTimedOut) {
          canvas.drawCircle(Offset(cx, cy), tileSize * 0.15, _redDot);
        }

        // Glow: original blurred halo, always drawn (baseline for measurement).
        if (state.flag == TileFlag.open && !state.exploded) {
          canvas.drawCircle(
              Offset(cx, cy), tileSize * 0.35, isDarkMode ? _glowDark : _glowLight);
        }

        if (isDarkMode) {
          canvas.drawRect(rect, _tileBorderDark);
        }

        // Hint numbers: immutable per coord, served from rules chunk cache.
        if (drawText && state.flag == TileFlag.open && !state.exploded) {
          final hint = game.rules.getHint(coord);
          if (hint > 0) {
            final tp = _hintPainter(
              hint.toString(),
              TextStyle(
                color: _hintColor(hint, isDarkMode),
                fontSize: tileSize * 0.6,
                fontWeight: FontWeight.bold,
              ),
            );
            tp.paint(
              canvas,
              Offset(cx - tp.width / 2, cy - tp.height / 2),
            );
          }
        }
      }
    }

    // Chunk grid as long lines (dozens of lines, not per-tile segments).
    // Always drawn. Locked chunks get a red outline.
    final minChunkX = MinesweeperGame.chunkOf(minX, chunkSize);
    final maxChunkX = MinesweeperGame.chunkOf(maxX, chunkSize);
    final minChunkY = MinesweeperGame.chunkOf(minY, chunkSize);
    final maxChunkY = MinesweeperGame.chunkOf(maxY, chunkSize);
    {
      final left = minX * tileSize;
      final right = (maxX + 1) * tileSize;
      final top = minY * tileSize;
      final bottom = (maxY + 1) * tileSize;
      for (int cx = minChunkX; cx <= maxChunkX + 1; cx++) {
        final dx = cx * chunkSize * tileSize;
        canvas.drawLine(Offset(dx, top), Offset(dx, bottom), chunkBorderPaint);
      }
      for (int cy = minChunkY; cy <= maxChunkY + 1; cy++) {
        final dy = cy * chunkSize * tileSize;
        canvas.drawLine(Offset(left, dy), Offset(right, dy), chunkBorderPaint);
      }
    }

    // Big lock badges: one per locked chunk, independent of any single
    // tile state. Fixes the old bug where the timer lived on the center
    // tile and vanished when that tile was open/flagged, zoomed out
    // (drawText == false), or simply off-screen.
    if (hasTimeouts) {
      _drawLockBadges(
        canvas,
        minChunkX: minChunkX,
        maxChunkX: maxChunkX,
        minChunkY: minChunkY,
        maxChunkY: maxChunkY,
      );
    }
    if (sw != null) {
      sw.stop();
      final count = (maxX - minX + 1) * (maxY - minY + 1);
      game.perf.recordRender(sw.elapsedMicroseconds / 1000.0, count, zoom);
    }
  }

  void _drawLockBadges(
    Canvas canvas, {
    required int minChunkX,
    required int maxChunkX,
    required int minChunkY,
    required int maxChunkY,
  }) {
    final tileSize = game.tileSize;
    final chunkSize = game.minesweeperWorld.chunkSize;
    final viewfinder = game.cameraComponent.viewfinder;
    final zoom = viewfinder.zoom;
    // Badge is ~3 tiles wide, so keep it down to ~48px chunk on screen
    // (far more forgiving than the old per-tile 10px text threshold).
    if (chunkSize * tileSize * zoom < 48.0) return;

    final cameraPos = viewfinder.position;
    final viewW = game.size.x / zoom;
    final viewH = game.size.y / zoom;
    final viewLeft = cameraPos.x - viewW / 2;
    final viewRight = cameraPos.x + viewW / 2;
    final viewTop = cameraPos.y - viewH / 2;
    final viewBottom = cameraPos.y + viewH / 2;
    final margin = tileSize * 2.0;
    final fontSize = tileSize * 1.1;

    double clampOrCenter(double v, double lo, double hi, double center) {
      if (lo >= hi) return center;
      return v.clamp(lo, hi).toDouble();
    }

    final viewCx = (viewLeft + viewRight) / 2;
    final viewCy = (viewTop + viewBottom) / 2;

    for (int cyy = minChunkY; cyy <= maxChunkY; cyy++) {
      for (int cxx = minChunkX; cxx <= maxChunkX; cxx++) {
        final timeout = game.getChunkTimeoutByChunk(cxx, cyy);
        if (!timeout.$1 || timeout.$2 == null) continue;

        // Expressive lock: shaded chunk + red outline.
        final chunkRect = Rect.fromLTWH(
          cxx * chunkSize * tileSize,
          cyy * chunkSize * tileSize,
          chunkSize * tileSize,
          chunkSize * tileSize,
        );
        canvas.drawRect(chunkRect, _lockedChunkShade);
        canvas.drawRect(chunkRect, _chunkBorderLocked);

        final remaining = timeout.$2!;
        final minutes = remaining.inMinutes;
        final seconds = remaining.inSeconds % 60;
        final text =
            '$minutes:${seconds.toString().padLeft(2, '0')}';
        final tp = _timerPainter(text, Colors.white, fontSize);

        // Clamp to the visible viewport so the badge stays on screen even
        // when the chunk center itself is scrolled out of view.
        final chunkCx = (cxx * chunkSize + chunkSize / 2) * tileSize;
        final chunkCy = (cyy * chunkSize + chunkSize / 2) * tileSize;
        final badgeCx = clampOrCenter(
            chunkCx, viewLeft + margin, viewRight - margin, viewCx);
        final badgeCy = clampOrCenter(
            chunkCy, viewTop + margin, viewBottom - margin, viewCy);

        final padH = tileSize * 0.55;
        final padV = tileSize * 0.35;
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(badgeCx, badgeCy),
            width: tp.width + padH * 2,
            height: tp.height + padV * 2,
          ),
          Radius.circular(tileSize * 0.5),
        );
        canvas.drawRRect(bgRect, _lockBadgeBg);
        canvas.drawRRect(bgRect, _lockBadgeBorder);
        tp.paint(
            canvas, Offset(badgeCx - tp.width / 2, badgeCy - tp.height / 2));
      }
    }
  }

  Color _hintColor(int hint, bool isDarkMode) {
    if (isDarkMode) {
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

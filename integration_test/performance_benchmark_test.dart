import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_timesweeper/core/models/coord.dart';
import 'package:infinite_timesweeper/core/models/tile_state.dart';
import 'package:infinite_timesweeper/core/models/world.dart' as core_models;
import 'package:infinite_timesweeper/core/perf/benchmark_stats.dart';
import 'package:infinite_timesweeper/core/perf/image_diff.dart';
import 'package:infinite_timesweeper/main.dart';
import 'package:integration_test/integration_test.dart';

const _schemaVersion = 2;
const _warmupFrames = 30;
const _measuredFrames = 200;
const _panStepPerFrame = 8.0;
const _visualChannelTolerance = 8;
const _visualDiffTolerance = 0.002; // 0.2% of pixels.
const _screenshotWidth = 800.0;
const _screenshotHeight = 600.0;
const _screenshotDir = String.fromEnvironment(
  'BENCH_SCREENSHOT_DIR',
  defaultValue: 'build/performance/screenshots',
);
const _referenceDir = String.fromEnvironment(
  'BENCH_REFERENCE_DIR',
  defaultValue: 'test/reference/performance',
);
const _updateReference = bool.fromEnvironment('BENCH_UPDATE_REFERENCE');

final _timings = <FrameTiming>[];
final _scenarios = <Map<String, Object>>[];
final _fixtureEpoch = DateTime.now();
final _surfaceChanges = <String>[];
double _devicePixelRatio = 1.0;
double _surfaceWidth = 0;
double _surfaceHeight = 0;
bool _surfaceInitialized = false;
bool _surfaceStable = true;
int _gameSequence = 0;

const _themes = <String>['light', 'dark'];

const _renderWorkloads = <_Workload>[
  _Workload('zoomed_out_static', 0.1),
  _Workload('zoomed_out_pan', 0.1),
  _Workload('text_cold', 0.5, coldCache: true),
  _Workload('text_warm', 0.5),
];

const _timeoutWorkload = _Workload(
  'zoomed_out_timeouts',
  0.1,
  includeExplosions: true,
);

class _Workload {
  const _Workload(
    this.name,
    this.zoom, {
    this.coldCache = false,
    this.includeExplosions = false,
  });

  final String name;
  final double zoom;
  final bool coldCache;
  final bool includeExplosions;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  SchedulerBinding.instance.addTimingsCallback(_timings.addAll);

  testWidgets('render and chunk-cache scenes in both themes', (tester) async {
    expect(
      kProfileMode,
      isTrue,
      reason: 'Run this benchmark with flutter drive --profile.',
    );
    for (final theme in _themes) {
      final game = await _loadGame(
        tester,
        _fixture(),
        brightness: _brightnessFor(theme),
      );
      _checkSurface(tester, game);
      for (final workload in _renderWorkloads) {
        await _runScene(tester, game, workload: workload, theme: theme);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  }, timeout: const Timeout(Duration(minutes: 90)));

  testWidgets('large world with pending timeouts in both themes', (
    tester,
  ) async {
    expect(kProfileMode, isTrue);
    for (final theme in _themes) {
      final game = await _loadGame(
        tester,
        _fixture(includeExplosions: true),
        brightness: _brightnessFor(theme),
      );
      _checkSurface(tester, game);
      await _runScene(tester, game, workload: _timeoutWorkload, theme: theme);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await _writeReport();
  }, timeout: const Timeout(Duration(minutes: 45)));
}

String _sceneName(_Workload workload, String theme) =>
    '${workload.name}_$theme';

Brightness _brightnessFor(String theme) =>
    theme == 'dark' ? Brightness.dark : Brightness.light;

Map<Coord, TileState> _fixture({bool includeExplosions = false}) {
  final tiles = <Coord, TileState>{};
  // Keep the timeout workload constant even when a slow candidate runs for
  // longer than the game's five-minute explosion expiry. The epoch is shared
  // with the screenshot clock freeze so the lock badges render deterministically.
  final openedAt = _fixtureEpoch.add(const Duration(hours: 1));
  const open = TileState(flag: TileFlag.open);
  const flagged = TileState(flag: TileFlag.flagged);
  const closed = TileState();
  for (var y = -180; y <= 180; y++) {
    for (var x = -240; x <= 240; x++) {
      final exploded = includeExplosions && x % 16 == 8 && y % 16 == 8;
      if (exploded) {
        tiles[Coord(x, y)] = TileState(
          flag: TileFlag.open,
          exploded: true,
          openedAt: openedAt,
        );
      } else if ((x - y) % 16 == 0) {
        tiles[Coord(x, y)] = open;
      } else if ((x + y) % 32 == 0) {
        tiles[Coord(x, y)] = flagged;
      } else {
        tiles[Coord(x, y)] = closed;
      }
    }
  }
  return tiles;
}

Future<MinesweeperGame> _loadGame(
  WidgetTester tester,
  Map<Coord, TileState> tiles, {
  required Brightness brightness,
}) async {
  final game = MinesweeperGame(
    initialWorld: core_models.World(
      seed: 'performance-v1',
      chunkSize: 16,
      minesPerChunk: 40,
      name: 'Performance benchmark',
      formatVersion: '1.0',
    ),
    initialTiles: tiles,
    enablePerfReporting: false,
    initialBrightness: brightness,
  );
  await tester.pumpWidget(
    GameWidget<MinesweeperGame>.controlled(
      // A fresh key ensures the GameWidget state (and thus the game instance)
      // is recreated for each theme instead of keeping the previous game.
      key: ValueKey('benchmark-game-${_gameSequence++}'),
      gameFactory: () => game,
    ),
  );
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!game.isLoaded && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(game.isLoaded, isTrue, reason: 'Game did not finish loading.');
  await Future<void>.delayed(const Duration(seconds: 2));
  return game;
}

void _checkSurface(WidgetTester tester, MinesweeperGame game) {
  expect(game.size.x, greaterThan(0));
  expect(game.size.y, greaterThan(0));
  _devicePixelRatio = tester.view.devicePixelRatio;
  expect(
    _devicePixelRatio,
    1.0,
    reason: 'Benchmark results require a 1x device pixel ratio.',
  );
  _recordSurface(game, 'game load');
}

void _recordSurface(MinesweeperGame game, String phase) {
  final width = game.size.x;
  final height = game.size.y;
  if (width <= 0 || height <= 0) {
    throw StateError('Benchmark surface is empty during $phase.');
  }
  if (!_surfaceInitialized) {
    _surfaceWidth = width;
    _surfaceHeight = height;
    _surfaceInitialized = true;
    return;
  }
  if (width != _surfaceWidth || height != _surfaceHeight) {
    _surfaceStable = false;
    final change =
        '$phase: ${_surfaceWidth.toStringAsFixed(0)}x'
        '${_surfaceHeight.toStringAsFixed(0)} -> '
        '${width.toStringAsFixed(0)}x${height.toStringAsFixed(0)}';
    if (!_surfaceChanges.contains(change)) {
      _surfaceChanges.add(change);
      stdout.writeln('BENCH_SURFACE_CHANGE=$change');
    }
  }
}

Map<String, Object> _surfaceSnapshot(MinesweeperGame game) => <String, Object>{
  'width': game.size.x,
  'height': game.size.y,
  'devicePixelRatio': _devicePixelRatio,
};

Future<void> _runScene(
  WidgetTester tester,
  MinesweeperGame game, {
  required _Workload workload,
  required String theme,
}) async {
  final name = _sceneName(workload, theme);
  stdout.writeln('BENCH_SCENE_START=$name');
  _recordSurface(game, '$name start');
  final sceneSurface = _surfaceSnapshot(game);
  game.benchmarkUpdate = null;
  game.benchmarkBeforeRender = null;
  game.cameraComponent.viewfinder.zoom = workload.zoom;
  game.cameraComponent.viewfinder.position = Vector2.zero();
  if (workload.name == 'zoomed_out_pan') {
    var panFrame = 0;
    game.benchmarkUpdate = (game, dt) {
      panFrame++;
      // Fixed work per frame: candidate speed cannot change scene coverage.
      game.cameraComponent.viewfinder.position = Vector2(
        _panStepPerFrame * panFrame,
        0,
      );
    };
  }
  game.benchmarkBeforeRender = workload.coldCache
      ? () => game.rules.clearChunkCache()
      : null;
  final cameraStart = game.cameraComponent.viewfinder.position.clone();

  final sceneStart = _latestBuildStart();
  await _waitForFrames(sceneStart, _warmupFrames);
  // Warm the renderer, not the cold-cache scene's generated hint data.
  if (workload.coldCache) {
    game.rules.resetChunkCache();
  } else {
    game.rules.resetChunkCacheStats();
  }
  final start = _latestBuildStart();
  await _waitForFrames(start, _measuredFrames);
  final end = _latestBuildStart();
  game.benchmarkBeforeRender = null;
  if (workload.name == 'zoomed_out_pan') {
    game.benchmarkUpdate = (game, dt) {
      game.cameraComponent.viewfinder.position = Vector2(
        _panStepPerFrame * 100,
        0,
      );
    };
  } else {
    game.benchmarkUpdate = null;
  }
  if (workload.includeExplosions) {
    game.benchmarkFrozenNow = _fixtureEpoch;
  }
  final cacheHits = game.rules.cacheHits;
  final cacheMisses = game.rules.cacheMisses;
  // FrameTiming reports are batched; retain the tail before slicing the window.
  await Future<void>.delayed(const Duration(seconds: 2));

  final samples =
      _timings.where((timing) {
        final timestamp = timing.timestampInMicroseconds(
          ui.FramePhase.buildStart,
        );
        return timestamp > start && timestamp <= end;
      }).toList()..sort(
        (a, b) => a
            .timestampInMicroseconds(ui.FramePhase.buildStart)
            .compareTo(b.timestampInMicroseconds(ui.FramePhase.buildStart)),
      );
  expect(
    samples.length,
    greaterThanOrEqualTo(_measuredFrames),
    reason: '$name did not produce enough measured frames.',
  );

  double milliseconds(Duration duration) => duration.inMicroseconds / 1000.0;
  final build = samples.map((t) => milliseconds(t.buildDuration)).toList();
  final raster = samples.map((t) => milliseconds(t.rasterDuration)).toList();
  final total = samples.map((t) => milliseconds(t.totalSpan)).toList();
  final intervals = <double>[];
  for (var i = 1; i < samples.length; i++) {
    intervals.add(
      (samples[i].timestampInMicroseconds(ui.FramePhase.buildStart) -
              samples[i - 1].timestampInMicroseconds(
                ui.FramePhase.buildStart,
              )) /
          1000.0,
    );
  }
  final meanInterval = intervals.reduce((a, b) => a + b) / intervals.length;
  final visibleWidth = (game.size.x / game.tileSize / workload.zoom).ceil() + 3;
  final visibleHeight =
      (game.size.y / game.tileSize / workload.zoom).ceil() + 3;
  final cameraDistance = game.cameraComponent.viewfinder.position.distanceTo(
    cameraStart,
  );
  var openTiles = 0;
  var flaggedTiles = 0;
  var explodedTiles = 0;
  for (final entry in game.storage.entries) {
    final state = entry.value;
    if (state.flag == TileFlag.open) openTiles++;
    if (state.flag == TileFlag.flagged) flaggedTiles++;
    if (state.exploded) explodedTiles++;
  }
  if (workload.name == 'zoomed_out_pan') {
    expect(
      cameraDistance,
      greaterThan(0),
      reason: 'The pan scene must actually move the camera.',
    );
  }

  final visual = await _captureOrReportError(
    tester,
    game,
    name,
    workload: workload,
  );
  _recordSurface(game, '$name end');
  final sceneSurfaceAfter = _surfaceSnapshot(game);
  final sceneStable =
      sceneSurface['width'] == sceneSurfaceAfter['width'] &&
      sceneSurface['height'] == sceneSurfaceAfter['height'];

  stdout.writeln('BENCH_SCENE_END=$name samples=${samples.length}');
  _scenarios.add(<String, Object>{
    'name': name,
    'brightness': theme,
    'surface': sceneSurface,
    'surfaceStable': sceneStable,
    'zoom': workload.zoom,
    'visibleTiles': visibleWidth * visibleHeight,
    'storedTiles': game.storage.count,
    'openTiles': openTiles,
    'flaggedTiles': flaggedTiles,
    'explodedTiles': explodedTiles,
    'sampleCount': samples.length,
    'cacheHits': cacheHits,
    'cacheMisses': cacheMisses,
    'cameraDistance': cameraDistance,
    'cameraStepPerFrame': workload.name == 'zoomed_out_pan'
        ? _panStepPerFrame
        : 0.0,
    'initialFrameTotalSpanMs': total.first,
    'estimatedFps': 1000.0 / meanInterval,
    'over16_7msRatio': total.where((ms) => ms > 16.7).length / total.length,
    'uiBuildMs': _summary(build),
    'rasterMs': _summary(raster),
    'totalSpanMs': _summary(total),
    'visual': visual,
  });
  _timings.removeWhere(
    (timing) => timing.timestampInMicroseconds(ui.FramePhase.buildStart) <= end,
  );
}

Future<Map<String, Object>> _captureOrReportError(
  WidgetTester tester,
  MinesweeperGame game,
  String name, {
  required _Workload workload,
}) async {
  try {
    return await _captureScreenshot(tester, game, name, workload: workload);
  } catch (error, stackTrace) {
    game.benchmarkUpdate = null;
    game.benchmarkFrozenNow = null;
    debugPrint('Screenshot capture failed for $name: $error\n$stackTrace');
    stdout.writeln('BENCH_VISUAL=$name status=error error=$error');
    return <String, Object>{
      'status': 'error',
      'diffRatio': 1.0,
      'differentPixels': 0,
      'maxChannelDelta': 0,
      'error': error.toString(),
    };
  }
}

Future<Map<String, Object>> _captureScreenshot(
  WidgetTester tester,
  MinesweeperGame game,
  String name, {
  required _Workload workload,
}) async {
  // Keep the fixed pan position applied after every game update so the
  // camera transform cannot reset it before the screenshot frame.
  if (workload.name == 'zoomed_out_pan') {
    game.benchmarkUpdate = (game, dt) {
      game.cameraComponent.viewfinder.position = Vector2(
        _panStepPerFrame * 100,
        0,
      );
    };
  }
  if (workload.includeExplosions) {
    // Freeze the countdown at the fixture epoch so timer text is stable.
    game.benchmarkFrozenNow = _fixtureEpoch;
  }
  late Uint8List png;
  try {
    final frameStart = _latestBuildStart();
    // Let the fixed camera/clock settle for a few rendered frames; FrameTiming
    // reports can lag behind the state change by more than two frames.
    await Future<void>.delayed(const Duration(seconds: 1));
    await _waitForFrames(frameStart, 3);
    png = await _capturePng(tester);
  } finally {
    game.benchmarkUpdate = null;
    game.benchmarkFrozenNow = null;
  }

  final screenshotFile = File('$_screenshotDir/$name.png');
  await _atomicWrite(screenshotFile, png);
  final referenceFile = File('$_referenceDir/$name.png');
  if (_updateReference) {
    await _atomicWrite(referenceFile, png);
    stdout.writeln('BENCH_VISUAL=$name status=updated');
    return <String, Object>{
      'status': 'updated',
      'diffRatio': 0.0,
      'differentPixels': 0,
      'maxChannelDelta': 0,
      'screenshot': screenshotFile.path,
      'reference': referenceFile.path,
    };
  }
  if (!await referenceFile.exists()) {
    stdout.writeln('BENCH_VISUAL=$name status=missing');
    return <String, Object>{
      'status': 'missing',
      'diffRatio': 1.0,
      'differentPixels': 0,
      'maxChannelDelta': 0,
      'screenshot': screenshotFile.path,
      'reference': referenceFile.path,
    };
  }

  final actual = await _decodePng(png);
  final expected = await _decodePng(await referenceFile.readAsBytes());
  if (actual.width != expected.width || actual.height != expected.height) {
    stdout.writeln('BENCH_VISUAL=$name status=mismatch dimensions');
    return <String, Object>{
      'status': 'mismatch',
      'diffRatio': 1.0,
      'differentPixels': actual.width * actual.height,
      'maxChannelDelta': 255,
      'screenshot': screenshotFile.path,
      'reference': referenceFile.path,
    };
  }
  final diff = compareRgba(
    actual.bytes,
    expected.bytes,
    width: actual.width,
    height: actual.height,
    channelTolerance: _visualChannelTolerance,
  );
  final status = diff.diffRatio <= _visualDiffTolerance ? 'match' : 'mismatch';
  stdout.writeln(
    'BENCH_VISUAL=$name status=$status diff=${(diff.diffRatio * 100).toStringAsFixed(3)}% '
    'pixels=${diff.differentPixels} max=${diff.maxChannelDelta}',
  );
  return <String, Object>{
    'status': status,
    'diffRatio': diff.diffRatio,
    'differentPixels': diff.differentPixels,
    'maxChannelDelta': diff.maxChannelDelta,
    'screenshot': screenshotFile.path,
    'reference': referenceFile.path,
  };
}

Future<Uint8List> _capturePng(WidgetTester tester) async {
  final view = tester.binding.renderViews.first;
  // The root RenderView is a repaint boundary, so its layer is an OffsetLayer.
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  if (layer is! OffsetLayer) {
    throw StateError('RenderView did not expose an OffsetLayer.');
  }
  final viewSize = view.size;
  if (viewSize.width < _screenshotWidth ||
      viewSize.height < _screenshotHeight) {
    throw StateError(
      'Benchmark window must be at least ${_screenshotWidth.toInt()}x'
      '${_screenshotHeight.toInt()}; got ${viewSize.width}x${viewSize.height}.',
    );
  }
  // A fixed, centred crop keeps the captured world region comparable when the
  // tiling window manager changes the overall window size.
  final captureRect = Rect.fromCenter(
    center: Offset(viewSize.width / 2, viewSize.height / 2),
    width: _screenshotWidth,
    height: _screenshotHeight,
  );
  final image = await layer.toImage(captureRect, pixelRatio: 1.0);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Could not encode the screenshot as PNG.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<({Uint8List bytes, int width, int height})> _decodePng(
  Uint8List bytes,
) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw StateError('Could not decode the reference screenshot.');
    }
    return (
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width: image.width,
      height: image.height,
    );
  } finally {
    image.dispose();
    codec.dispose();
  }
}

Future<void> _atomicWrite(File file, List<int> bytes) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsBytes(bytes, flush: true);
  await temporary.rename(file.path);
}

int _latestBuildStart() {
  if (_timings.isEmpty) return 0;
  return _timings
      .map((timing) => timing.timestampInMicroseconds(ui.FramePhase.buildStart))
      .reduce((a, b) => a > b ? a : b);
}

Future<void> _waitForFrames(int after, int count) async {
  final deadline = DateTime.now().add(const Duration(minutes: 15));
  while (DateTime.now().isBefore(deadline)) {
    final frames = _timings
        .where(
          (timing) =>
              timing.timestampInMicroseconds(ui.FramePhase.buildStart) > after,
        )
        .length;
    if (frames >= count) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  final frames = _timings
      .where(
        (timing) =>
            timing.timestampInMicroseconds(ui.FramePhase.buildStart) > after,
      )
      .length;
  throw TimeoutException('Received $frames of $count requested frames.');
}

Map<String, double> _summary(List<double> samples) => {
  'p50': percentile(samples, 0.50),
  'p95': percentile(samples, 0.95),
  'p99': percentile(samples, 0.99),
};

Future<void> _writeReport() async {
  final score = geometricMean(
    _scenarios.map(
      (scene) => (scene['totalSpanMs']! as Map<String, double>)['p95']!,
    ),
  );
  final report = <String, Object>{
    'schemaVersion': _schemaVersion,
    'score': score,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'metadata': <String, Object>{
      'flutterVersion': const String.fromEnvironment('BENCH_FLUTTER_VERSION'),
      'gitRevision': const String.fromEnvironment('BENCH_GIT_REVISION'),
      'loadAverageAtRunStart': const String.fromEnvironment(
        'BENCH_LOAD_AVERAGE',
      ),
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'surface': <String, Object>{
        'width': _surfaceWidth,
        'height': _surfaceHeight,
        'devicePixelRatio': _devicePixelRatio,
      },
      'surfaceStable': _surfaceStable,
      'surfaceChanges': _surfaceChanges,
      'screenshotSize': <String, Object>{
        'width': _screenshotWidth,
        'height': _screenshotHeight,
      },
      'warmupFrames': _warmupFrames,
      'minimumMeasuredFrames': _measuredFrames,
      'themeMatrix': _themes,
      'visualDiffTolerance': _visualDiffTolerance,
      'visualChannelTolerance': _visualChannelTolerance,
      'screenshotDirectory': _screenshotDir,
      'referenceDirectory': _referenceDir,
      'referenceUpdateMode': _updateReference,
      'scoreFormula': 'geometric mean of scenario p95 totalSpan milliseconds',
      'over16_7msDefinition': 'fraction of frames with totalSpan > 16.7 ms',
    },
    'scenarios': _scenarios,
  };
  final output = File(
    const String.fromEnvironment(
      'BENCH_OUT',
      defaultValue: 'build/performance/benchmark.json',
    ),
  );
  await _atomicWrite(
    output,
    utf8.encode(const JsonEncoder.withIndent('  ').convert(report)),
  );
  stdout.writeln('PERF_BENCHMARK_JSON=${output.absolute.path}');
  if (_updateReference) {
    await _writeReferenceManifest();
  }
}

Future<void> _writeReferenceManifest() async {
  final manifest = <String, Object>{
    'schemaVersion': _schemaVersion,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'flutterVersion': const String.fromEnvironment('BENCH_FLUTTER_VERSION'),
    'gitRevision': const String.fromEnvironment('BENCH_GIT_REVISION'),
    'surface': <String, Object>{
      'width': _surfaceWidth,
      'height': _surfaceHeight,
      'devicePixelRatio': _devicePixelRatio,
    },
    'surfaceStable': _surfaceStable,
    'surfaceChanges': _surfaceChanges,
    'screenshotSize': <String, Object>{
      'width': _screenshotWidth,
      'height': _screenshotHeight,
    },
    'warmupFrames': _warmupFrames,
    'minimumMeasuredFrames': _measuredFrames,
    'scenes': _scenarios.map((scene) => scene['name']).toList(),
    'note':
        'Reference screenshots are '
        '${_screenshotWidth.toInt()}x${_screenshotHeight.toInt()} centred crops '
        'tied to this Linux environment (Flutter version, fonts, and GPU stack). '
        'Regenerate them on the same machine after intentional visual changes.',
  };
  await _atomicWrite(
    File('$_referenceDir/manifest.json'),
    utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
  );
}

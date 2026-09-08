import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_timesweeper/core/models/coord.dart';
import 'package:infinite_timesweeper/core/models/world.dart';
import 'package:infinite_timesweeper/core/perf/frame_stats.dart';
import 'package:infinite_timesweeper/core/rules/rules_engine.dart';
import 'package:infinite_timesweeper/core/storage/storage.dart';

void main() {
  test('chunk cache hit/miss counters increment', () {
    final world = World(
      seed: 'perf',
      chunkSize: 16,
      minesPerChunk: 40,
      name: 'p',
      formatVersion: '1.0',
    );
    final storage = TileStorage();
    final rules = RulesEngine(world, storage);

    expect(rules.cacheHits, 0);
    expect(rules.cacheMisses, 0);
    rules.getHint(const Coord(0, 0));
    expect(rules.cacheMisses, 1);
    rules.getHint(const Coord(1, 1)); // same chunk -> hit
    expect(rules.cacheHits, 1);
  });

  test('FrameStats throttles reports and mentions key metrics', () {
    final stats = FrameStats();
    stats.recordFrame(1 / 60);
    stats.recordRender(2.5, 2695, 1.0);
    expect(stats.maybeReport(0.5, storedTiles: 10, chunkHits: 1, chunkMisses: 1),
        isNull);
    final report = stats.maybeReport(2.0,
        storedTiles: 10, chunkHits: 1, chunkMisses: 1);
    expect(report, isNotNull);
    expect(report, contains('render_avg'));
    expect(report, contains('tiles=2695'));
    expect(report, contains('chunkHit='));
  });
}

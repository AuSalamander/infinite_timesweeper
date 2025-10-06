import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_timesweeper/core/models/world.dart';
import 'package:infinite_timesweeper/core/models/coord.dart';
import 'package:infinite_timesweeper/core/chunk/generator.dart';

void main() {
  group('generateChunk', () {
    // Helper to create test worlds
    World createTestWorld({
      String seed = 'test',
      int chunkSize = 5,
      int minesPerChunk = 5,
      String name = 'test',
      String formatVersion = '1',
    }) {
      return World(
        seed: seed,
        chunkSize: chunkSize,
        minesPerChunk: minesPerChunk,
        name: name,
        formatVersion: formatVersion,
      );
    }

    test(
        'produces identical chunk data when called multiple times with same parameters',
        () {
      final world = createTestWorld();
      final chunk1 = generateChunk(world, 0, 0);
      final chunk2 = generateChunk(world, 0, 0);

      // Deep equality check for all coordinates
      expect(chunk1.length, equals(chunk2.length));
      for (final coord in chunk1.keys) {
        expect(chunk1[coord], equals(chunk2[coord]),
            reason: 'Mismatch at $coord');
      }
    });

    test('produces different results for different world seeds', () {
      final world1 = createTestWorld(seed: 'seed1');
      final world2 = createTestWorld(seed: 'seed2');
      final chunk1 = generateChunk(world1, 0, 0);
      final chunk2 = generateChunk(world2, 0, 0);

      // Verify at least one difference exists
      bool foundDifference = false;
      for (final coord in chunk1.keys) {
        if (chunk1[coord] != chunk2[coord]) {
          foundDifference = true;
          break;
        }
      }
      expect(foundDifference, isTrue,
          reason: 'No differences found between different seeds');
    });

    test('produces different results for different chunk positions', () {
      final world = createTestWorld();
      final chunk00 = generateChunk(world, 0, 0);
      final chunk01 = generateChunk(world, 0, 1);

      // Verify at least one difference exists
      bool foundDifference = false;
      for (final coord in chunk00.keys) {
        final shiftedCoord = Coord(coord.x, coord.y + world.chunkSize);
        if (chunk00[coord] != chunk01[shiftedCoord]) {
          foundDifference = true;
          break;
        }
      }
      expect(foundDifference, isTrue,
          reason: 'No differences found between adjacent chunks');
    });

    test('maintains consistency with non-zero chunk coordinates', () {
      final world = createTestWorld();
      final chunk10 = generateChunk(world, 1, 0);
      final chunk10Again = generateChunk(world, 1, 0);

      // Deep equality check
      expect(chunk10.length, equals(chunk10Again.length));
      for (final coord in chunk10.keys) {
        expect(chunk10[coord], equals(chunk10Again[coord]),
            reason: 'Mismatch at $coord');
      }
    });

    test('produces different results when minesPerChunk changes', () {
      final world1 = createTestWorld(minesPerChunk: 3);
      final world2 = createTestWorld(minesPerChunk: 10);
      final chunk1 = generateChunk(world1, 0, 0);
      final chunk2 = generateChunk(world2, 0, 0);

      // Verify at least one mine count difference
      bool foundMineDifference = false;
      for (final coord in chunk1.keys) {
        // Mine locations should differ when minesPerChunk changes
        if ((chunk1[coord] == -1) != (chunk2[coord] == -1)) {
          foundMineDifference = true;
          break;
        }
      }
      expect(foundMineDifference, isTrue,
          reason: 'Mine patterns identical despite different minesPerChunk');
    });
  });
}

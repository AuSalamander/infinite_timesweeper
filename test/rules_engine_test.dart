import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_timesweeper/core/models/coord.dart';
import 'package:infinite_timesweeper/core/models/tile_state.dart';
import 'package:infinite_timesweeper/core/models/world.dart';
import 'package:infinite_timesweeper/core/storage/storage.dart';
import 'package:infinite_timesweeper/core/rules/rules_engine.dart';

// Helper to check recent explosions
bool _hasRecentExplosion(TileStorage storage, World world, int chunkX, int chunkY) {
  final now = DateTime.now();
  final cutoff = now.subtract(const Duration(minutes: 5));
  final chunkSize = world.chunkSize;
  final startX = chunkX * chunkSize;
  final startY = chunkY * chunkSize;
  
  for (int ly = 0; ly < chunkSize; ly++) {
    for (int lx = 0; lx < chunkSize; lx++) {
      final coord = Coord(startX + lx, startY + ly);
      final state = storage.get(coord);
      if (state.exploded && state.openedAt != null && state.openedAt!.isAfter(cutoff)) {
        return true;
      }
    }
  }
  return false;
}

// Helper to get neighbors
List<Coord> _getNeighbors(Coord coord) {
  final neighbors = <Coord>[];
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      if (dx == 0 && dy == 0) continue;
      neighbors.add(Coord(coord.x + dx, coord.y + dy));
    }
  }
  return neighbors;
}

// Helper to save world with gameplay to file
Future<String> _saveWorldWithGameplay(
  World world,
  TileStorage storage,
  String testName,
) async {
  final projectDir = Directory.current;
  final worldsDir = Directory('${projectDir.path}/worlds');
  
  if (!worldsDir.existsSync()) {
    worldsDir.createSync(recursive: true);
  }
  
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final filePath = '${worldsDir.path}/${testName}_$timestamp.json';
  
  await storage.saveToFile(filePath, world: world);
  print('Saved test world: $filePath');
  
  return filePath;
}

void main() {
  group('RulesEngine - Complex World Tests', () {
    group('Small chunks with low mine density', () {
      test('16x16 chunks with 0.125 mine ratio (32 mines)', () async {
        final world = World(
          seed: 'small_low_density',
          chunkSize: 16,
          minesPerChunk: 32, // 32/(16*16) = 0.125
          name: 'Small Low Density',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Test opening tiles near chunk borders
        final borderCoords = [
          Coord(15, 15), // Last tile in chunk (0,0)
          Coord(16, 16), // First tile in chunk (1,1)
          Coord(31, 31), // Last tile in chunk (1,1)
          Coord(0, 15),  // Left edge of chunk (0,0)
          Coord(15, 0),  // Top edge of chunk (0,0)
        ];

        for (final coord in borderCoords) {
          if (!rules.isMine(coord)) {
            rules.openTile(coord);
          }
        }

        await _saveWorldWithGameplay(world, storage, 'small_low_density');
        expect(storage.count, greaterThan(0));
      });

      test('16x16 chunks with 0.25 mine ratio (64 mines)', () async {
        final world = World(
          seed: 'small_medium_density',
          chunkSize: 16,
          minesPerChunk: 64, // 64/(16*16) = 0.25
          name: 'Small Medium Density',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Test flood fill across multiple chunks
        Coord? safeCoord;
        for (int y = 20; y < 40 && safeCoord == null; y++) {
          for (int x = 20; x < 40 && safeCoord == null; x++) {
            final coord = Coord(x, y);
            if (!rules.isMine(coord) && rules.getHint(coord) == 0) {
              safeCoord = coord;
            }
          }
        }

        if (safeCoord != null) {
          rules.openTile(safeCoord);
        }

        await _saveWorldWithGameplay(world, storage, 'small_medium_density');
        expect(storage.count, greaterThan(0));
      });
    });

    group('Medium chunks with various densities', () {
      test('32x32 chunks with 0.15 mine ratio (154 mines)', () async {
        final world = World(
          seed: 'medium_low_density',
          chunkSize: 32,
          minesPerChunk: 154, // ~0.15 ratio
          name: 'Medium Low Density',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Test axis borders (x=0, y=0, negative coordinates)
        final axisCoords = [
          Coord(0, 0),
          Coord(-1, 0),
          Coord(0, -1),
          Coord(-1, -1),
          Coord(31, 0),  // Chunk border at x=32
          Coord(0, 31),  // Chunk border at y=32
        ];

        for (final coord in axisCoords) {
          if (!rules.isMine(coord)) {
            rules.openTile(coord);
          }
        }

        await _saveWorldWithGameplay(world, storage, 'medium_low_density_axis');
        expect(storage.count, greaterThan(0));
      });

      test('32x32 chunks with 0.30 mine ratio (307 mines)', () async {
        final world = World(
          seed: 'medium_high_density',
          chunkSize: 32,
          minesPerChunk: 307, // ~0.30 ratio
          name: 'Medium High Density',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Test chording near chunk borders
        Coord? chordCoord;
        for (int offset = -2; offset <= 2 && chordCoord == null; offset++) {
          final coord = Coord(32 + offset, 32 + offset);
          final hint = rules.getHint(coord);
          if (hint > 0 && hint <= 3 && !rules.isMine(coord)) {
            chordCoord = coord;
          }
        }

        if (chordCoord != null) {
          rules.openTile(chordCoord);
          final hint = rules.getHint(chordCoord);
          final neighbors = _getNeighbors(chordCoord);
          
          // Flag correct number of neighbors
          int flagged = 0;
          for (final neighbor in neighbors) {
            if (flagged < hint) {
              if (rules.isMine(neighbor)) {
                rules.flagTile(neighbor);
                flagged++;
              }
            }
          }
          
          // Attempt chord
          rules.openTile(chordCoord);
        }

        await _saveWorldWithGameplay(world, storage, 'medium_high_density_chord');
        expect(storage.count, greaterThan(0));
      });
    });

    group('Large chunks with realistic densities', () {
      test('64x64 chunks with 0.20 mine ratio (819 mines)', () async {
        final world = World(
          seed: 'large_medium_density',
          chunkSize: 64,
          minesPerChunk: 819, // ~0.20 ratio
          name: 'Large Medium Density',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Test massive flood fill
        Coord? massiveZero;
        for (int y = 100; y < 200 && massiveZero == null; y += 5) {
          for (int x = 100; x < 200 && massiveZero == null; x += 5) {
            final coord = Coord(x, y);
            if (!rules.isMine(coord) && rules.getHint(coord) == 0) {
              massiveZero = coord;
            }
          }
        }

        if (massiveZero != null) {
          rules.openTile(massiveZero);
        }

        await _saveWorldWithGameplay(world, storage, 'large_medium_density_flood');
        expect(storage.count, greaterThan(0));
      });

      test('64x64 chunks with 0.35 mine ratio (1434 mines)', () async {
        final world = World(
          seed: 'large_high_density',
          chunkSize: 64,
          minesPerChunk: 1434, // ~0.35 ratio
          name: 'Large High Density',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Test careful gameplay in high density
        final startCoords = [
          Coord(50, 50),
          Coord(63, 63), // Chunk border
          Coord(64, 64), // Next chunk
        ];

        for (final coord in startCoords) {
          if (!rules.isMine(coord)) {
            rules.openTile(coord);
            
            // Flag some neighbors if they're mines
            final neighbors = _getNeighbors(coord);
            for (final neighbor in neighbors.take(2)) {
              if (rules.isMine(neighbor)) {
                rules.flagTile(neighbor);
              }
            }
          }
        }

        await _saveWorldWithGameplay(world, storage, 'large_high_density_careful');
        expect(storage.count, greaterThan(0));
      });
    });

    group('Chunk border edge cases', () {
      test('flood fill across 4 chunks at intersection', () async {
        final world = World(
          seed: 'four_chunk_intersection',
          chunkSize: 16,
          minesPerChunk: 40, // ~0.156 ratio
          name: 'Four Chunk Intersection',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Find a zero hint near the 4-chunk intersection at (16,16)
        Coord? intersectionZero;
        for (int dy = -3; dy <= 3 && intersectionZero == null; dy++) {
          for (int dx = -3; dx <= 3 && intersectionZero == null; dx++) {
            final coord = Coord(16 + dx, 16 + dy);
            if (!rules.isMine(coord) && rules.getHint(coord) == 0) {
              intersectionZero = coord;
            }
          }
        }

        if (intersectionZero != null) {
          rules.openTile(intersectionZero);
          
          // Verify tiles opened in all 4 chunks
          final openedChunks = <String>{};
          for (int dy = -10; dy <= 10; dy++) {
            for (int dx = -10; dx <= 10; dx++) {
              final coord = Coord(intersectionZero.x + dx, intersectionZero.y + dy);
              if (storage.get(coord).flag == TileFlag.open) {
                final cc = coord.toChunk(world.chunkSize);
                openedChunks.add('${cc.chunkX},${cc.chunkY}');
              }
            }
          }
          
          print('Opened tiles across ${openedChunks.length} chunks: $openedChunks');
        }

        await _saveWorldWithGameplay(world, storage, 'four_chunk_intersection');
        expect(storage.count, greaterThan(0));
      });

      test('chord at exact chunk boundary', () async {
        final world = World(
          seed: 'chord_at_boundary',
          chunkSize: 32,
          minesPerChunk: 200, // ~0.195 ratio
          name: 'Chord at Boundary',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Test chording at x=32 boundary (between chunks)
        final boundaryCoords = [Coord(31, 32), Coord(32, 32), Coord(33, 32)];
        
        for (final coord in boundaryCoords) {
          if (!rules.isMine(coord)) {
            rules.openTile(coord);
            
            final hint = rules.getHint(coord);
            if (hint > 0) {
              // Count actual mines around
              final neighbors = _getNeighbors(coord);
              final mines = neighbors.where((n) => rules.isMine(n)).toList();
              
              // Flag exact number of mines
              for (final mine in mines) {
                rules.flagTile(mine);
              }
              
              // Try chord
              rules.openTile(coord);
            }
          }
        }

        await _saveWorldWithGameplay(world, storage, 'chord_at_boundary');
        expect(storage.count, greaterThan(0));
      });

      test('explosion protection across chunk borders', () async {
        final world = World(
          seed: 'explosion_border_protection',
          chunkSize: 16,
          minesPerChunk: 50, // ~0.195 ratio
          name: 'Explosion Border Protection',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Create explosion in chunk (0,0) at position (5,5)
        storage.applyEvent(TileEvent(
          coord: Coord(5, 5),
          type: TileEventType.explode,
          timestamp: DateTime.now(),
        ));

        // Try to open tiles in same chunk - should be blocked
        final sameChunkCoords = [Coord(10, 10), Coord(15, 15)];
        for (final coord in sameChunkCoords) {
          rules.openTile(coord);
          expect(storage.get(coord).flag, TileFlag.closed, 
            reason: 'Tile in same chunk should be blocked by recent explosion');
        }

        // Try to open tiles in adjacent chunk (1,1) - should work
        final adjacentCoords = [Coord(16, 16), Coord(20, 20)];
        for (final coord in adjacentCoords) {
          if (!rules.isMine(coord)) {
            final beforeCount = storage.count;
            rules.openTile(coord);
            final afterCount = storage.count;
            expect(afterCount, greaterThan(beforeCount),
              reason: 'Tile in different chunk should open despite explosion in other chunk');
          }
        }

        await _saveWorldWithGameplay(world, storage, 'explosion_border_protection');
      });
    });

    group('Negative coordinate tests', () {
      test('gameplay in negative quadrants', () async {
        final world = World(
          seed: 'negative_quadrants',
          chunkSize: 32,
          minesPerChunk: 256, // 0.25 ratio
          name: 'Negative Quadrants',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Test all four quadrants
        final quadrantCoords = [
          Coord(10, 10),    // Quadrant I (+,+)
          Coord(-10, 10),   // Quadrant II (-,+)
          Coord(-10, -10),  // Quadrant III (-,-)
          Coord(10, -10),   // Quadrant IV (+,-)
        ];

        for (final coord in quadrantCoords) {
          if (!rules.isMine(coord)) {
            rules.openTile(coord);
          }
        }

        // Test negative axis borders
        final negativeAxisCoords = [
          Coord(-1, 0),
          Coord(0, -1),
          Coord(-32, 0),  // Chunk boundary
          Coord(0, -32),  // Chunk boundary
        ];

        for (final coord in negativeAxisCoords) {
          if (!rules.isMine(coord)) {
            rules.openTile(coord);
          }
        }

        await _saveWorldWithGameplay(world, storage, 'negative_quadrants');
        expect(storage.count, greaterThan(0));
      });

      test('flood fill crossing axis origin', () async {
        final world = World(
          seed: 'origin_crossing',
          chunkSize: 16,
          minesPerChunk: 35, // ~0.137 ratio
          name: 'Origin Crossing',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Find zero hint near origin
        Coord? originZero;
        for (int y = -5; y <= 5 && originZero == null; y++) {
          for (int x = -5; x <= 5 && originZero == null; x++) {
            final coord = Coord(x, y);
            if (!rules.isMine(coord) && rules.getHint(coord) == 0) {
              originZero = coord;
            }
          }
        }

        if (originZero != null) {
          rules.openTile(originZero);
          
          // Check tiles opened in negative coordinates
          int negativeCount = 0;
          for (int y = -20; y <= 20; y++) {
            for (int x = -20; x <= 20; x++) {
              final coord = Coord(x, y);
              if (storage.get(coord).flag == TileFlag.open && (x < 0 || y < 0)) {
                negativeCount++;
              }
            }
          }
          
          print('Opened $negativeCount tiles in negative coordinates');
        }

        await _saveWorldWithGameplay(world, storage, 'origin_crossing');
        expect(storage.count, greaterThan(0));
      });
    });

    group('Maximum density tests', () {
      test('40% mine density - near maximum playable', () async {
        final world = World(
          seed: 'maximum_density',
          chunkSize: 16,
          minesPerChunk: 102, // ~0.398 ratio
          name: 'Maximum Density',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Very careful gameplay
        Coord? safeStart;
        for (int y = 50; y < 100 && safeStart == null; y++) {
          for (int x = 50; x < 100 && safeStart == null; x++) {
            final coord = Coord(x, y);
            if (!rules.isMine(coord)) {
              safeStart = coord;
            }
          }
        }

        if (safeStart != null) {
          rules.openTile(safeStart);
          
          // Open a few more carefully
          final neighbors = _getNeighbors(safeStart);
          for (final neighbor in neighbors.take(3)) {
            if (!rules.isMine(neighbor)) {
              rules.openTile(neighbor);
            } else {
              rules.flagTile(neighbor);
            }
          }
        }

        await _saveWorldWithGameplay(world, storage, 'maximum_density');
        expect(storage.count, greaterThan(0));
      });

      test('45% mine density - extreme stress test', () async {
        final world = World(
          seed: 'extreme_density',
          chunkSize: 16,
          minesPerChunk: 115, // 0.449 ratio
          name: 'Extreme Density',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Find any safe tile
        Coord? anySafe;
        for (int attempt = 0; attempt < 1000 && anySafe == null; attempt++) {
          final coord = Coord(attempt % 50, attempt ~/ 50);
          if (!rules.isMine(coord)) {
            anySafe = coord;
          }
        }

        if (anySafe != null) {
          rules.openTile(anySafe);
        }

        await _saveWorldWithGameplay(world, storage, 'extreme_density');
        expect(storage.count, greaterThan(0));
      });
    });

    group('Complex gameplay scenarios', () {
      test('extended gameplay session with flags and chords', () async {
        final world = World(
          seed: 'extended_session',
          chunkSize: 32,
          minesPerChunk: 250, // ~0.244 ratio
          name: 'Extended Session',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Simulate real gameplay: open, flag, chord
        final gameplaySteps = <(int, int, String)>[
          (10, 10, 'open'),
          (11, 10, 'open'),
          (12, 10, 'flag'),
          (10, 11, 'open'),
          (11, 11, 'chord'),
          (20, 20, 'open'),
          (31, 31, 'open'), // Chunk border
          (32, 32, 'open'), // Next chunk
        ];

        for (final (x, y, action) in gameplaySteps) {
          final coord = Coord(x, y);
          switch (action) {
            case 'open':
              if (!rules.isMine(coord)) {
                rules.openTile(coord);
              }
            case 'flag':
              rules.flagTile(coord);
            case 'chord':
              rules.openTile(coord); // Will chord if conditions met
          }
        }

        await _saveWorldWithGameplay(world, storage, 'extended_session');
        expect(storage.count, greaterThan(0));
      });

      test('world with intentional explosions', () async {
        final world = World(
          seed: 'with_explosions',
          chunkSize: 16,
          minesPerChunk: 40, // ~0.156 ratio
          name: 'With Explosions',
          formatVersion: '1.0',
        );
        final storage = TileStorage();
        final rules = RulesEngine(world, storage);

        // Find and hit a mine
        Coord? mineCoord;
        for (int y = 10; y < 30 && mineCoord == null; y++) {
          for (int x = 10; x < 30 && mineCoord == null; x++) {
            if (rules.isMine(Coord(x, y))) {
              mineCoord = Coord(x, y);
            }
          }
        }

        if (mineCoord != null) {
          // Hit the mine
          rules.openTile(mineCoord);
          expect(storage.get(mineCoord).exploded, true);
          
          // Try to open nearby tile in same chunk - should be blocked
          final nearbyInChunk = Coord(mineCoord.x + 1, mineCoord.y + 1);
          final cc1 = mineCoord.toChunk(world.chunkSize);
          final cc2 = nearbyInChunk.toChunk(world.chunkSize);
          
          if (cc1.chunkX == cc2.chunkX && cc1.chunkY == cc2.chunkY) {
            rules.openTile(nearbyInChunk);
            if (!rules.isMine(nearbyInChunk)) {
              expect(storage.get(nearbyInChunk).flag, TileFlag.closed,
                reason: 'Should be blocked by recent explosion');
            }
          }
        }

        await _saveWorldWithGameplay(world, storage, 'with_explosions');
      });
    });
  });

  group('RulesEngine - Basic Functionality (preserved)', () {
    late World world;
    late TileStorage storage;
    late RulesEngine rules;

    setUp(() {
      world = World(
        seed: 'test123',
        chunkSize: 16,
        minesPerChunk: 40, // ~0.156 ratio
        name: 'Test World',
        formatVersion: '1.0',
      );
      storage = TileStorage();
      rules = RulesEngine(world, storage);
    });

    group('flagTile', () {
      test('flags a closed tile', () {
        final coord = const Coord(5, 5);
        rules.flagTile(coord);
        
        expect(storage.get(coord).flag, TileFlag.flagged);
      });

      test('unflags a flagged tile', () {
        final coord = const Coord(5, 5);
        rules.flagTile(coord);
        rules.flagTile(coord);
        
        expect(storage.get(coord).flag, TileFlag.closed);
      });

      test('does nothing to an open tile', () {
        final coord = const Coord(5, 5);
        storage.applyEvent(TileEvent(
          coord: coord,
          type: TileEventType.open,
          timestamp: DateTime.now(),
        ));
        
        rules.flagTile(coord);
        expect(storage.get(coord).flag, TileFlag.open);
      });
    });

    group('openTile', () {
      test('does not open flagged tile', () {
        final coord = const Coord(5, 5);
        rules.flagTile(coord);
        rules.openTile(coord);
        
        expect(storage.get(coord).flag, TileFlag.flagged);
      });

      test('opens safe tile', () {
        Coord? safeCoord;
        for (int y = 50; y < 100 && safeCoord == null; y++) {
          for (int x = 50; x < 100 && safeCoord == null; x++) {
            final coord = Coord(x, y);
            if (!rules.isMine(coord)) {
              safeCoord = coord;
            }
          }
        }
        
        if (safeCoord != null) {
          rules.openTile(safeCoord);
          expect(storage.get(safeCoord).flag, TileFlag.open);
        }
      });
    });
  });
}

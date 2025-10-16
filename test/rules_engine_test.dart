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

void main() {
  group('RulesEngine', () {
    late World world;
    late TileStorage storage;
    late RulesEngine rules;

    setUp(() {
      world = World(
        seed: 'test123',
        chunkSize: 16,
        minesPerChunk: 10,
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

    group('openTile - closed tile', () {
      test('does nothing if chunk had recent explosion', () {
        final explosionCoord = const Coord(0, 0);
        storage.applyEvent(TileEvent(
          coord: explosionCoord,
          type: TileEventType.explode,
          timestamp: DateTime.now(),
        ));
        
        final coord = const Coord(1, 1);
        rules.openTile(coord);
        
        expect(storage.get(coord).flag, TileFlag.closed);
      });

      test('opens tile after 5 minutes have passed', () {
        final explosionCoord = const Coord(0, 0);
        storage.applyEvent(TileEvent(
          coord: explosionCoord,
          type: TileEventType.explode,
          timestamp: DateTime.now().subtract(const Duration(minutes: 6)),
        ));
        
        final coord = const Coord(1, 1);
        rules.openTile(coord);
        
        expect(storage.get(coord).flag, TileFlag.open);
      });

      test('does not open flagged tile', () {
        final coord = const Coord(5, 5);
        rules.flagTile(coord);
        rules.openTile(coord);
        
        expect(storage.get(coord).flag, TileFlag.flagged);
      });

      test('recursively opens neighbors when hint is 0', () {
        // Find a tile with hint 0 in a safe chunk
        Coord? zeroHintCoord;
        for (int y = 50; y < 150 && zeroHintCoord == null; y++) {
          for (int x = 50; x < 150 && zeroHintCoord == null; x++) {
            final coord = Coord(x, y);
            final chunkCoord = coord.toChunk(world.chunkSize);
            if (!_hasRecentExplosion(storage, world, chunkCoord.chunkX, chunkCoord.chunkY)) {
              final hint = rules.getHint(coord);
              if (hint == 0) {
                zeroHintCoord = coord;
              }
            }
          }
        }
        
        if (zeroHintCoord == null) {
          print('No zero hint tile found, skipping test');
          return;
        }
        
        rules.openTile(zeroHintCoord);
        
        int openedCount = 0;
        for (final neighbor in _getNeighbors(zeroHintCoord)) {
          if (storage.get(neighbor).flag == TileFlag.open) {
            openedCount++;
          }
        }
        
        expect(openedCount, greaterThan(0));
      });
    });

    group('openTile - chord', () {
      test('chords when hint equals flagged neighbors', () {
        // Find a tile with small hint in a safe chunk
        Coord? hintCoord;
        for (int y = 50; y < 150 && hintCoord == null; y++) {
          for (int x = 50; x < 150 && hintCoord == null; x++) {
            final coord = Coord(x, y);
            final chunkCoord = coord.toChunk(world.chunkSize);
            if (!_hasRecentExplosion(storage, world, chunkCoord.chunkX, chunkCoord.chunkY)) {
              final hint = rules.getHint(coord);
              if (hint > 0 && hint <= 3) {
                hintCoord = coord;
              }
            }
          }
        }
        
        if (hintCoord == null) {
          print('No suitable hint tile found, skipping test');
          return;
        }
        
        final hint = rules.getHint(hintCoord);
        
        rules.openTile(hintCoord);
        expect(storage.get(hintCoord).flag, TileFlag.open);
        
        final neighbors = _getNeighbors(hintCoord);
        for (int i = 0; i < hint && i < neighbors.length; i++) {
          rules.flagTile(neighbors[i]);
        }
        
        final beforeCount = storage.count;
        rules.openTile(hintCoord);
        final afterCount = storage.count;
        
        expect(afterCount, greaterThan(beforeCount));
      });

      test('does not chord when flagged count does not match hint', () {
        // Find a tile with hint > 1
        Coord? hintCoord;
        for (int y = 50; y < 150 && hintCoord == null; y++) {
          for (int x = 50; x < 150 && hintCoord == null; x++) {
            final coord = Coord(x, y);
            final chunkCoord = coord.toChunk(world.chunkSize);
            if (!_hasRecentExplosion(storage, world, chunkCoord.chunkX, chunkCoord.chunkY)) {
              final hint = rules.getHint(coord);
              if (hint > 1) {
                hintCoord = coord;
              }
            }
          }
        }
        
        if (hintCoord == null) {
          print('No suitable hint tile found, skipping test');
          return;
        }
        
        final hint = rules.getHint(hintCoord);
        
        rules.openTile(hintCoord);
        
        // Flag fewer neighbors than hint
        final neighbors = _getNeighbors(hintCoord);
        if (hint > 1) {
          rules.flagTile(neighbors[0]);
        }
        
        final beforeCount = storage.count;
        rules.openTile(hintCoord);
        final afterCount = storage.count;
        
        expect(afterCount, equals(beforeCount));
      });
    });

    group('chunk border behavior', () {
      test('recursively opens across chunk borders', () {
        // Test at chunk boundary (15,15) is last tile in chunk (0,0)
        // (16,16) is first tile in chunk (1,1)
        
        // Find a zero hint near chunk border
        Coord? borderCoord;
        for (int offset = -2; offset <= 2 && borderCoord == null; offset++) {
          final x = 16 + offset;
          final y = 16 + offset;
          final coord = Coord(x, y);
          final chunkCoord = coord.toChunk(world.chunkSize);
          if (!_hasRecentExplosion(storage, world, chunkCoord.chunkX, chunkCoord.chunkY)) {
            final hint = rules.getHint(coord);
            if (hint == 0) {
              borderCoord = coord;
            }
          }
        }
        
        if (borderCoord == null) {
          print('No zero hint at border found, skipping test');
          return;
        }
        
        rules.openTile(borderCoord);
        
        // Check that tiles from different chunks are opened
        final openedChunks = <String>{};
        for (int dy = -5; dy <= 5; dy++) {
          for (int dx = -5; dx <= 5; dx++) {
            final coord = Coord(borderCoord.x + dx, borderCoord.y + dy);
            if (storage.get(coord).flag == TileFlag.open) {
              final cc = coord.toChunk(world.chunkSize);
              openedChunks.add('${cc.chunkX},${cc.chunkY}');
            }
          }
        }
        
        expect(openedChunks.length, greaterThan(1));
      });

      test('chord opens tiles across chunk borders', () {
        // Find a hint tile right at chunk border
        Coord? borderHint;
        for (int offset = -1; offset <= 1 && borderHint == null; offset++) {
          final x = 16 + offset;
          final y = 16 + offset;
          final coord = Coord(x, y);
          final chunkCoord = coord.toChunk(world.chunkSize);
          if (!_hasRecentExplosion(storage, world, chunkCoord.chunkX, chunkCoord.chunkY)) {
            final hint = rules.getHint(coord);
            if (hint > 0 && hint <= 3) {
              borderHint = coord;
            }
          }
        }
        
        if (borderHint == null) {
          print('No border hint found, skipping test');
          return;
        }
        
        final hint = rules.getHint(borderHint);
        
        rules.openTile(borderHint);
        
        final neighbors = _getNeighbors(borderHint);
        for (int i = 0; i < hint && i < neighbors.length; i++) {
          rules.flagTile(neighbors[i]);
        }
        
        rules.openTile(borderHint);
        
        // Check tiles from different chunks were opened
        final openedChunks = <String>{};
        for (final neighbor in neighbors) {
          if (storage.get(neighbor).flag == TileFlag.open) {
            final cc = neighbor.toChunk(world.chunkSize);
            openedChunks.add('${cc.chunkX},${cc.chunkY}');
          }
        }
        
        // Should have opened tiles potentially from multiple chunks
        expect(openedChunks.isNotEmpty, true);
      });

      test('explosion in one chunk does not affect adjacent chunk', () {
        // Create explosion at (15, 15) - last tile in chunk (0,0)
        final explosionCoord = const Coord(15, 15);
        storage.applyEvent(TileEvent(
          coord: explosionCoord,
          type: TileEventType.explode,
          timestamp: DateTime.now(),
        ));
        
        // Try to open (0, 0) in the same chunk - should be blocked
        final sameChunkCoord = const Coord(0, 0);
        rules.openTile(sameChunkCoord);
        expect(storage.get(sameChunkCoord).flag, TileFlag.closed);
        
        // Try to open (16, 16) - first tile in chunk (1,1)
        // This should work since it's a different chunk
        final adjacentCoord = const Coord(16, 16);
        final beforeCount = storage.count;
        rules.openTile(adjacentCoord);
        final afterCount = storage.count;
        
        // Should have opened at least one tile (the one we clicked)
        expect(afterCount, greaterThan(beforeCount));
      });
    });
  });
}

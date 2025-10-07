import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_timesweeper/core/storage/tile_storage.dart';
import 'package:infinite_timesweeper/core/models/coord.dart';
import 'package:infinite_timesweeper/core/models/tile_state.dart';

void main() {
  group('TileStorage', () {
    late TileStorage storage;

    setUp(() {
      storage = TileStorage();
    });

    test('get returns default state for unmodified tile', () {
      final coord = Coord(0, 0);
      final state = storage.get(coord);

      expect(state.flag, TileFlag.closed);
      expect(state.exploded, false);
      expect(state.openedAt, null);
    });

    test('applyEvent open changes tile state', () {
      final coord = Coord(5, 10);
      final timestamp = DateTime.now();
      final event = TileEvent(
        coord: coord,
        type: TileEventType.open,
        timestamp: timestamp,
      );

      storage.applyEvent(event);
      final state = storage.get(coord);

      expect(state.flag, TileFlag.open);
      expect(state.openedAt, timestamp);
    });

    test('applyEvent flag changes tile state', () {
      final coord = Coord(3, 7);
      final event = TileEvent(
        coord: coord,
        type: TileEventType.flag,
        timestamp: DateTime.now(),
      );

      storage.applyEvent(event);
      final state = storage.get(coord);

      expect(state.flag, TileFlag.flagged);
    });

    test('applyEvent unflag changes tile state', () {
      final coord = Coord(2, 4);

      // First flag it
      storage.applyEvent(TileEvent(
        coord: coord,
        type: TileEventType.flag,
        timestamp: DateTime.now(),
      ));

      // Then unflag it
      storage.applyEvent(TileEvent(
        coord: coord,
        type: TileEventType.unflag,
        timestamp: DateTime.now(),
      ));

      final state = storage.get(coord);
      expect(state.flag, TileFlag.closed);
    });

    test('applyEvent explode changes tile state', () {
      final coord = Coord(1, 1);
      final timestamp = DateTime.now();
      final event = TileEvent(
        coord: coord,
        type: TileEventType.explode,
        timestamp: timestamp,
      );

      storage.applyEvent(event);
      final state = storage.get(coord);

      expect(state.exploded, true);
      expect(state.flag, TileFlag.open);
      expect(state.openedAt, timestamp);
    });

    test('snapshot returns copy of all modified tiles', () {
      final coord1 = Coord(0, 0);
      final coord2 = Coord(1, 1);

      storage.applyEvent(TileEvent(
        coord: coord1,
        type: TileEventType.open,
        timestamp: DateTime.now(),
      ));

      storage.applyEvent(TileEvent(
        coord: coord2,
        type: TileEventType.flag,
        timestamp: DateTime.now(),
      ));

      final snapshot = storage.snapshot();

      expect(snapshot.length, 2);
      expect(snapshot[coord1]?.flag, TileFlag.open);
      expect(snapshot[coord2]?.flag, TileFlag.flagged);
    });

    test('clear removes all stored tiles', () {
      storage.applyEvent(TileEvent(
        coord: Coord(0, 0),
        type: TileEventType.open,
        timestamp: DateTime.now(),
      ));

      storage.clear();

      expect(storage.count, 0);
      expect(storage.get(Coord(0, 0)).flag, TileFlag.closed);
    });

    test('saveToFile and loadFromFile persist data', () {
      // find path
      final projectDir = Directory.current;
      final worldsDir = Directory('${projectDir.path}/worlds');

      // create worlds folder
      if (!worldsDir.existsSync()) {
        worldsDir.createSync(recursive: true);
        print('Created directory for test worlds: ${worldsDir.path}');
      }

      // generate world name
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${worldsDir.path}/world_$timestamp.json';
      print('New test world saving: $filePath');

      final coord = Coord(10, 20);
      final timestampNow = DateTime.now();

      // applying event to world file
      storage.applyEvent(TileEvent(
        coord: coord,
        type: TileEventType.open,
        timestamp: timestampNow,
      ));

      // save to file
      storage.saveToFile(filePath).then((_) {
        // check
        expect(File(filePath).existsSync(), true);

        // load from file
        final newStorage = TileStorage();
        newStorage.loadFromFile(filePath).then((_) {
          final state = newStorage.get(coord);
          expect(state.flag, TileFlag.open);
          expect(state.openedAt?.toIso8601String(), timestampNow.toIso8601String());
        });
      });
    });

    test('saveToFile and loadFromFile with multiple complex actions', () async {
      // Path to the 'worlds' folder in the project root
      final projectDir = Directory.current;
      final worldsDir = Directory('${projectDir.path}/worlds');

      if (!worldsDir.existsSync()) {
        worldsDir.createSync(recursive: true);
      }

      // Unique file for this test
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${worldsDir.path}/complex_world_$timestamp.json';
      print('Saving complex world: $filePath');

      // 1. Apply DIFFERENT actions to different tiles
      final events = [
        // Open tile (3,4) at 15:00
        TileEvent(
          coord: Coord(3, 4),
          type: TileEventType.open,
          timestamp: DateTime(2024, 1, 1, 15, 0, 0),
        ),
        // Place a flag on (5,7) at 15:01
        TileEvent(
          coord: Coord(5, 7),
          type: TileEventType.flag,
          timestamp: DateTime(2024, 1, 1, 15, 1, 0),
        ),
        // Remove flag from (5,7) at 15:02 (should become closed)
        TileEvent(
          coord: Coord(5, 7),
          type: TileEventType.unflag,
          timestamp: DateTime(2024, 1, 1, 15, 2, 0),
        ),
        // Explode (1,1) at 15:03 (should become open and exploded)
        TileEvent(
          coord: Coord(1, 1),
          type: TileEventType.explode,
          timestamp: DateTime(2024, 1, 1, 15, 3, 0),
        ),
        // Open (9,9) at 15:04
        TileEvent(
          coord: Coord(9, 9),
          type: TileEventType.open,
          timestamp: DateTime(2024, 1, 1, 15, 4, 0),
        ),
      ];

      // Apply all events to the storage
      for (final event in events) {
        storage.applyEvent(event);
      }

      // 2. Save to file
      await storage.saveToFile(filePath);
      expect(File(filePath).existsSync(), true, reason: 'File should have been created');

      // 3. Load into a NEW storage instance
      final loadedStorage = TileStorage();
      await loadedStorage.loadFromFile(filePath);

      // 4. Verify EACH tile individually
      // (1) Tile (3,4) — opened at 15:00
      final state1 = loadedStorage.get(Coord(3, 4));
      expect(state1.flag, TileFlag.open);
      expect(state1.openedAt, DateTime(2024, 1, 1, 15, 0, 0));

      // (2) Tile (5,7) — after unflag should be closed
      final state2 = loadedStorage.get(Coord(5, 7));
      expect(state2.flag, TileFlag.closed);
      expect(state2.openedAt, null);

      // (3) Tile (1,1) — exploded and open
      final state3 = loadedStorage.get(Coord(1, 1));
      expect(state3.exploded, true);
      expect(state3.flag, TileFlag.open);
      expect(state3.openedAt, DateTime(2024, 1, 1, 15, 3, 0));

      // (4) Tile (9,9) — opened at 15:04
      final state4 = loadedStorage.get(Coord(9, 9));
      expect(state4.flag, TileFlag.open);
      expect(state4.openedAt, DateTime(2024, 1, 1, 15, 4, 0));

      // (5) Verify that UNCHANGED tiles behave correctly
      final state5 = loadedStorage.get(Coord(0, 0));
      expect(state5.flag, TileFlag.closed);
      expect(state5.exploded, false);

      // 5. Additional check: number of modified tiles
      expect(loadedStorage.count, 4, reason: 'There should be exactly 4 modified tiles');
    });

    test('realistic gameplay session saves correctly', () async {
      // File path
      final filePath = '${Directory.current.path}/worlds/realistic_world_${DateTime.now().millisecondsSinceEpoch}.json';

      // Simulate gameplay: opening tiles, placing flags, explosions
      final actions = [
        (Coord(0, 0), TileEventType.open),
        (Coord(1, 0), TileEventType.flag),
        (Coord(2, 0), TileEventType.open),
        (Coord(1, 0), TileEventType.unflag), // Remove flag
        (Coord(0, 1), TileEventType.open),
        (Coord(1, 1), TileEventType.explode), // Explosion!
      ];

      // Apply actions with delay (simulating real gameplay)
      for (int i = 0; i < actions.length; i++) {
        final (coord, type) = actions[i];
        storage.applyEvent(TileEvent(
          coord: coord,
          type: type,
          timestamp: DateTime.now().add(Duration(seconds: i)),
        ));
        await Future.delayed(Duration(milliseconds: 100)); // Simulate pause between clicks
      }

      // Save
      await storage.saveToFile(filePath);

      // Load
      final loaded = TileStorage();
      await loaded.loadFromFile(filePath);

      // Verify key points
      expect(loaded.get(Coord(1, 1)).exploded, true, reason: 'Tile should be exploded');
      expect(loaded.get(Coord(1, 0)).flag, TileFlag.closed, reason: 'Flag should have been removed');
      expect(loaded.get(Coord(0, 0)).flag, TileFlag.open, reason: 'Tile should be open');
    });

    test('loadFromFile handles non-existent file', () async {
      await storage.loadFromFile('/non/existent/file.json');
      expect(storage.count, 0);
    });
  });

  group('TileEvent', () {
    test('toJson and fromJson are inverse operations', () {
      final event = TileEvent(
        coord: Coord(5, 10),
        type: TileEventType.flag,
        timestamp: DateTime.now(),
      );

      final json = event.toJson();
      final restored = TileEvent.fromJson(json);

      expect(restored.coord, event.coord);
      expect(restored.type, event.type);
      expect(restored.timestamp.toIso8601String(),
          event.timestamp.toIso8601String());
    });
  });
}

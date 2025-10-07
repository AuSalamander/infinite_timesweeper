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
        print('Создана папка для сохранений: ${worldsDir.path}');
      }

      // generate world name
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${worldsDir.path}/world_$timestamp.json';
      print('Сохраняю тестовый мир: $filePath');

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

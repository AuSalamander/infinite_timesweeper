import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_timesweeper/core/models/world.dart';

void main() {
  group('World Class Tests', () {
    test('should create World object with correct values', () {
      final world = World(
        seed: 'abc123',
        chunkSize: 16,
        minesPerChunk: 48,
        name: 'World_1',
        formatVersion: '1',
      );

      expect(world.seed, 'abc123');
      expect(world.chunkSize, 16);
      expect(world.minesPerChunk, 48);
      expect(world.name, 'World_1');
      expect(world.formatVersion, '1');
    });

    test('should serialize to JSON correctly', () {
      final world = World(
        seed: 'abc123',
        chunkSize: 16,
        minesPerChunk: 48,
        name: 'World_1',
        formatVersion: '1',
      );

      final jsonString = world.toJson();
      final expectedJson = '{"seed":"abc123","chunkSize":16,"minesPerChunk":48,"name":"World_1","formatVersion":"1"}';

      expect(jsonString, expectedJson);
    });

    test('should deserialize from JSON correctly', () {
      final jsonString = '{"seed":"abc123","chunkSize":16,"minesPerChunk":48,"name":"World_1","formatVersion":"1"}';
      final world = World.fromJson(jsonString);

      expect(world.seed, 'abc123');
      expect(world.chunkSize, 16);
      expect(world.minesPerChunk, 48);
      expect(world.name, 'World_1');
      expect(world.formatVersion, '1');
    });

    test('should round-trip serialize and deserialize without data loss', () {
      final originalWorld = World(
        seed: 'test_seed_123',
        chunkSize: 32,
        minesPerChunk: 25,
        name: 'My Test World',
        formatVersion: '2.0',
      );

      final jsonString = originalWorld.toJson();
      final deserializedWorld = World.fromJson(jsonString);

      expect(deserializedWorld.seed, originalWorld.seed);
      expect(deserializedWorld.chunkSize, originalWorld.chunkSize);
      expect(deserializedWorld.minesPerChunk, originalWorld.minesPerChunk);
      expect(deserializedWorld.name, originalWorld.name);
      expect(deserializedWorld.formatVersion, originalWorld.formatVersion);
    });

    test('should throw error if required fields are missing in JSON', () {
      final incompleteJson = '{"seed":"abc123","chunkSize":16,"minesPerChunk":48,"name":"World_1"}'; // Missing formatVersion

      expect(() => World.fromJson(incompleteJson), throwsA(isA<ArgumentError>()));
    });
  });
}

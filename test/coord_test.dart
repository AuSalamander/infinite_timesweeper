import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_timesweeper/core/models/coord.dart';

void main() {
  group('Coord', () {
    test('Coordinates (0,0) → chunk (0,0), local (0,0)', () {
      final coord = Coord(0, 0);
      final chunk = coord.toChunk(16);
      expect(chunk.chunkX, 0);
      expect(chunk.chunkY, 0);
      expect(chunk.localX, 0);
      expect(chunk.localY, 0);
    });

    test('Coordinates (15,15) → chunk (0,0), local (15,15)', () {
      final coord = Coord(15, 15);
      final chunk = coord.toChunk(16);
      expect(chunk.chunkX, 0);
      expect(chunk.chunkY, 0);
      expect(chunk.localX, 15);
      expect(chunk.localY, 15);
    });

    test('Coordinates (16,16) → chunk (1,1), local (0,0)', () {
      final coord = Coord(16, 16);
      final chunk = coord.toChunk(16);
      expect(chunk.chunkX, 1);
      expect(chunk.chunkY, 1);
      expect(chunk.localX, 0);
      expect(chunk.localY, 0);
    });

    test('Negative coordinates (-1,-1) → chunk (-1,-1), local (15,15)', () {
      final coord = Coord(-1, -1);
      final chunk = coord.toChunk(16);
      expect(chunk.chunkX, -1);
      expect(chunk.chunkY, -1);
      expect(chunk.localX, 15);
      expect(chunk.localY, 15);
    });

    test('Consistency: transformation and reverse calculation', () {
      // Проверяем, что x = чанкX * размер + локальныйX
      for (final x in [-100, -16, -1, 0, 1, 15, 16, 100]) {
        for (final y in [-100, -16, -1, 0, 1, 15, 16, 100]) {
          final coord = Coord(x, y);
          final chunk = coord.toChunk(16);
          final reconstructedX = chunk.chunkX * 16 + chunk.localX;
          final reconstructedY = chunk.chunkY * 16 + chunk.localY;
          expect(reconstructedX, x);
          expect(reconstructedY, y);
        }
      }
    });

    test('Coordinates comparison: (10,5) == (10,5)', () {
      final a = Coord(10, 5);
      final b = Coord(10, 5);
      expect(a == b, isTrue);
    });

    test('Coordinates comparison: (10,5) != (10,6)', () {
      final a = Coord(10, 5);
      final b = Coord(10, 6);
      expect(a == b, isFalse);
    });

    test('Save/load JSON', () {
      final coord = Coord(42, 13);
      final json = coord.toJson();
      final restored = Coord.fromJson(json);
      expect(restored.x, 42);
      expect(restored.y, 13);
    });
  });
}

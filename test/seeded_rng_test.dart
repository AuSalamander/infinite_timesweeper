import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_timesweeper/core/rng/seeded_rng.dart';

void main() {
  group('SeededRng', () {
    test('consistency with same seed', () {
      final rng1 = SeededRng(12345);
      final rng2 = SeededRng(12345);

      for (int i = 0; i < 100; i++) {
        expect(rng1.nextDouble(), equals(rng2.nextDouble()));
        expect(rng1.nextInt(1000), equals(rng2.nextInt(1000)));
      }
    });

    test('different seeds produce different sequences', () {
      final rng1 = SeededRng(12345);
      final rng2 = SeededRng(12346);

      bool foundDifference = false;
      for (int i = 0; i < 100; i++) {
        if (rng1.nextDouble() != rng2.nextDouble()) {
          foundDifference = true;
          break;
        }
      }
      expect(foundDifference, isTrue);
    });

    test('nextInt throws on invalid max', () {
      final rng = SeededRng(12345);
      expect(() => rng.nextInt(0), throwsArgumentError);
      expect(() => rng.nextInt(-1), throwsArgumentError);
    });

    test('nextInt returns values in correct range', () {
      final rng = SeededRng(12345);
      for (int i = 0; i < 1000; i++) {
        final value = rng.nextInt(10);
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThan(10));
      }
    });

    test('nextDouble returns values in [0,1)', () {
      final rng = SeededRng(12345);
      for (int i = 0; i < 1000; i++) {
        final value = rng.nextDouble();
        expect(value, greaterThanOrEqualTo(0.0));
        expect(value, lessThan(1.0));
      }
    });
  });

  group('combineSeed', () {
    test('consistency with same parameters', () {
      final seed1 = combineSeed(12345, 10, 20);
      final seed2 = combineSeed(12345, 10, 20);
      expect(seed1, equals(seed2));
    });

    test('different world seeds produce different results', () {
      final seed1 = combineSeed(12345, 10, 20);
      final seed2 = combineSeed(12346, 10, 20);
      expect(seed1, isNot(equals(seed2)));
    });

    test('different chunk coordinates produce different results', () {
      final seed1 = combineSeed(12345, 10, 20);
      final seed2 = combineSeed(12345, 11, 20);
      expect(seed1, isNot(equals(seed2)));

      final seed3 = combineSeed(12345, 10, 20);
      final seed4 = combineSeed(12345, 10, 21);
      expect(seed3, isNot(equals(seed4)));
    });

    test('generator salt affects result', () {
      final seed1 = combineSeed(12345, 10, 20, generatorSalt: 0);
      final seed2 = combineSeed(12345, 10, 20, generatorSalt: 1);
      expect(seed1, isNot(equals(seed2)));
    });

    test('zero generator salt same as no salt', () {
      final seed1 = combineSeed(12345, 10, 20);
      final seed2 = combineSeed(12345, 10, 20, generatorSalt: 0);
      expect(seed1, equals(seed2));
    });
  });

  group('generateChunkBitmap', () {
    test('consistency with same parameters', () {
      final bitmap1 = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 10,
        chunkY: 20,
        chunkSize: 16,
        minesPerChunk: 20,
      );
      final bitmap2 = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 10,
        chunkY: 20,
        chunkSize: 16,
        minesPerChunk: 20,
      );

      expect(bitmap1, equals(bitmap2));
    });

    test('different world seeds produce different results', () {
      final bitmap1 = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 10,
        chunkY: 20,
        chunkSize: 16,
        minesPerChunk: 20,
      );
      final bitmap2 = generateChunkBitmap(
        worldSeed: 12346,
        chunkX: 10,
        chunkY: 20,
        chunkSize: 16,
        minesPerChunk: 20,
      );

      expect(bitmap1, isNot(equals(bitmap2)));
    });

    test('different chunk coordinates produce different results', () {
      final bitmap1 = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 10,
        chunkY: 20,
        chunkSize: 16,
        minesPerChunk: 20,
      );
      final bitmap2 = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 11,
        chunkY: 20,
        chunkSize: 16,
        minesPerChunk: 20,
      );

      expect(bitmap1, isNot(equals(bitmap2)));
    });

    test('different generator salt produces different results', () {
      final bitmap1 = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 10,
        chunkY: 20,
        chunkSize: 16,
        minesPerChunk: 20,
        generatorSalt: 0,
      );
      final bitmap2 = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 10,
        chunkY: 20,
        chunkSize: 16,
        minesPerChunk: 20,
        generatorSalt: 1,
      );

      expect(bitmap1, isNot(equals(bitmap2)));
    });

    test('correct number of mines', () {
      for (int size in [8, 16, 32]) {
        for (int mines in [0, 1, size * size ~/ 4, size * size - 1, size * size]) {
          final bitmap = generateChunkBitmap(
            worldSeed: 12345,
            chunkX: 0,
            chunkY: 0,
            chunkSize: size,
            minesPerChunk: mines,
          );

          expect(bitmap.length, equals(size * size));

          int mineCount = 0;
          for (int cell in bitmap) {
            if (cell == 1) mineCount++;
          }

          expect(mineCount, equals(mines.clamp(0, size * size)));
        }
      }
    });

    test('minesPerChunk clamping works', () {
      final bitmap1 = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 0,
        chunkY: 0,
        chunkSize: 4,
        minesPerChunk: -5, // should be clamped to 0
      );
      expect(bitmap1.every((cell) => cell == 0), isTrue);

      final bitmap2 = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 0,
        chunkY: 0,
        chunkSize: 4,
        minesPerChunk: 20, // should be clamped to 16
      );
      expect(bitmap2.every((cell) => cell == 1), isTrue);
    });

    test('empty chunk has no mines', () {
      final bitmap = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 0,
        chunkY: 0,
        chunkSize: 16,
        minesPerChunk: 0,
      );
      expect(bitmap.every((cell) => cell == 0), isTrue);
    });

    test('full chunk has all mines', () {
      final bitmap = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 0,
        chunkY: 0,
        chunkSize: 4,
        minesPerChunk: 16,
      );
      expect(bitmap.every((cell) => cell == 1), isTrue);
    });

    test('row-major order', () {
      // Small chunk to make the test manageable
      final bitmap = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 0,
        chunkY: 0,
        chunkSize: 2,
        minesPerChunk: 2,
      );

      expect(bitmap.length, equals(4));
      // Index 0 = y=0, x=0
      // Index 1 = y=0, x=1
      // Index 2 = y=1, x=0
      // Index 3 = y=1, x=1
    });
  });

  group('bitmapToBitString', () {
    test('converts correctly without newlines', () {
      final bitmap = Uint8List.fromList([0, 1, 1, 0]);
      final result = bitmapToBitString(bitmap);
      expect(result, equals('0110'));
    });

    test('converts correctly with newlines', () {
      final bitmap = Uint8List.fromList([0, 1, 1, 0]);
      final result = bitmapToBitString(bitmap, chunkSize: 2);
      expect(result, equals('01\n10'));
    });

    test('handles different chunk sizes', () {
      final bitmap = Uint8List.fromList([0, 1, 1, 0, 1, 1]);
      final result = bitmapToBitString(bitmap, chunkSize: 3);
      expect(result, equals('011\n011'));
    });
  });

  group('packBitmapToBytes and unpackBytesToBitmap', () {
    test('pack and unpack are inverses', () {
      final original = Uint8List.fromList([0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 1, 1]);
      final packed = packBitmapToBytes(original);
      final unpacked = unpackBytesToBitmap(packed, original.length);

      expect(unpacked, equals(original));
    });

    test('pack handles non-multiple-of-8 lengths', () {
      final original = Uint8List.fromList([0, 1, 1, 0, 1]); // 5 bits
      final packed = packBitmapToBytes(original);
      final unpacked = unpackBytesToBitmap(packed, original.length);

      expect(unpacked, equals(original));
      expect(packed.length, equals(1)); // ceil(5/8) = 1
    });

    test('pack handles exactly 8 bits', () {
      final original = Uint8List.fromList([0, 1, 1, 0, 1, 0, 0, 1]);
      final packed = packBitmapToBytes(original);
      final unpacked = unpackBytesToBitmap(packed, original.length);

      expect(unpacked, equals(original));
      expect(packed.length, equals(1)); // exactly 1 byte
    });

    test('pack handles multiple of 8 bits', () {
      final original = Uint8List.fromList([0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 1, 1, 0, 0, 1, 1]);
      final packed = packBitmapToBytes(original);
      final unpacked = unpackBytesToBitmap(packed, original.length);

      expect(unpacked, equals(original));
      expect(packed.length, equals(2)); // exactly 2 bytes
    });

    test('packing preserves all bits', () {
      for (int size = 1; size <= 20; size++) {
        final original = Uint8List(size);
        // Fill with a pattern
        for (int i = 0; i < size; i++) {
          original[i] = i % 2;
        }

        final packed = packBitmapToBytes(original);
        final unpacked = unpackBytesToBitmap(packed, original.length);

        expect(unpacked, equals(original));
      }
    });
  });

  group('Integration tests', () {
    test('full pipeline consistency', () {
      final worldSeed = 12345;
      final chunkX = 10;
      final chunkY = 20;
      final chunkSize = 16;
      final minesPerChunk = 20;

      // Generate bitmap
      final bitmap1 = generateChunkBitmap(
        worldSeed: worldSeed,
        chunkX: chunkX,
        chunkY: chunkY,
        chunkSize: chunkSize,
        minesPerChunk: minesPerChunk,
      );

      // Pack and unpack
      final packed = packBitmapToBytes(bitmap1);
      final bitmap2 = unpackBytesToBitmap(packed, chunkSize * chunkSize);

      expect(bitmap1, equals(bitmap2));

      // Generate same bitmap again to ensure consistency
      final bitmap3 = generateChunkBitmap(
        worldSeed: worldSeed,
        chunkX: chunkX,
        chunkY: chunkY,
        chunkSize: chunkSize,
        minesPerChunk: minesPerChunk,
      );

      expect(bitmap1, equals(bitmap3));
    });

    test('different parameters produce different results through full pipeline', () {
      final bitmap1 = generateChunkBitmap(
        worldSeed: 12345,
        chunkX: 10,
        chunkY: 20,
        chunkSize: 16,
        minesPerChunk: 20,
      );

      final bitmap2 = generateChunkBitmap(
        worldSeed: 12346, // different world seed
        chunkX: 10,
        chunkY: 20,
        chunkSize: 16,
        minesPerChunk: 20,
      );

      expect(bitmap1, isNot(equals(bitmap2)));
    });
  });
}

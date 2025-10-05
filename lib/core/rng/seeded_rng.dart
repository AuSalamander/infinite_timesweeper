import 'dart:typed_data';

/// 64-bit SplitMix-like PRNG for determinism.
/// Not cryptographically secure, but fine for game generation.
class SeededRng {
  int _state; // use Dart int (arbitrary precision), we'll mask to 64-bit when needed
  SeededRng(int seed) : _state = seed & _mask64;

  static const int _mask64 = 0xFFFFFFFFFFFFFFFF;

  int _next64() {
    // splitmix64
    _state = (_state + 0x9E3779B97F4A7C15) & _mask64;
    var z = _state;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9 & _mask64;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB & _mask64;
    return (z ^ (z >> 31)) & _mask64;
  }

  /// Double in [0,1)
  double nextDouble() {
    final v = _next64() >> 11; // 53 bits
    return v / (1 << 53);
  }

  /// Integer in [0, max)
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError('max must be > 0');
    // use nextDouble * max — simple, deterministic, tiny bias negligible for game usage
    return (nextDouble() * max).floor();
  }
}

/// Combine worldSeed and chunk coordinates into single 64-bit seed.
int combineSeed(int worldSeed, int chunkX, int chunkY, {int generatorSalt = 0}) {
  const int mask = 0xFFFFFFFFFFFFFFFF;
  int a = (worldSeed & mask) ^ ((chunkX & mask) * 0x9E3779B97F4A7C15 & mask);
  int b = (a ^ ((chunkY & mask) * 0xC2B2AE3D27D4EB4F & mask)) & mask;
  if (generatorSalt != 0) {
    b = (b ^ ((generatorSalt & mask) << 17)) & mask;
  }
  return b;
}

/// Generate a chunk bitmap: Uint8List length = chunkSize*chunkSize, values 0/1.
/// Guarantees exactly minesPerChunk mines (clamped to [0, nCells]).
/// Order: row-major (y increasing, x increasing), index = y * chunkSize + x
Uint8List generateChunkBitmap({
  required int worldSeed,
  required int chunkX,
  required int chunkY,
  required int chunkSize,
  required int minesPerChunk,
  int generatorSalt = 0,
}) {
  final int n = chunkSize * chunkSize;
  final k = minesPerChunk.clamp(0, n);
  final result = Uint8List(n);

  if (k == 0) return result;
  if (k == n) {
    for (int i = 0; i < n; i++) result[i] = 1;
    return result;
  }

  final seed = combineSeed(worldSeed, chunkX, chunkY, generatorSalt: generatorSalt);
  final rng = SeededRng(seed);

  // Partial Fisher-Yates: select first k items after partial shuffle
  // We'll create an index array [0..n-1] but only partially shuffle first k positions.
  final indices = List<int>.generate(n, (i) => i);
  for (int i = 0; i < k; i++) {
    final j = i + rng.nextInt(n - i); // j in [i, n-1]
    final tmp = indices[i];
    indices[i] = indices[j];
    indices[j] = tmp;
    result[indices[i]] = 1; // mark as mine
  }

  return result;
}

/// Helper: convert bitmap to '0'/'1' string for debug
String bitmapToBitString(Uint8List bitmap, {int chunkSize = -1}) {
  final sb = StringBuffer();
  for (int i = 0; i < bitmap.length; i++) {
    sb.write(bitmap[i] == 1 ? '1' : '0');
    if (chunkSize > 0 && (i + 1) % chunkSize == 0 && i != bitmap.length - 1) {
      sb.write('\n'); // newline per row for readability
    }
  }
  return sb.toString();
}

/// Pack 0/1 bytes into bits (8 cells per byte). Useful for saving to disk.
Uint8List packBitmapToBytes(Uint8List bitmap) {
  final int n = bitmap.length;
  final int bytes = (n + 7) >> 3;
  final out = Uint8List(bytes);
  for (int i = 0; i < n; i++) {
    if (bitmap[i] == 1) {
      final bIndex = i >> 3;
      final bitPos = i & 7;
      out[bIndex] |= (1 << bitPos);
    }
  }
  return out;
}

/// Unpack bytes -> bitmap (reverse)
Uint8List unpackBytesToBitmap(Uint8List packed, int nCells) {
  final out = Uint8List(nCells);
  for (int i = 0; i < nCells; i++) {
    final bIndex = i >> 3;
    final bitPos = i & 7;
    if ((packed[bIndex] & (1 << bitPos)) != 0) out[i] = 1;
  }
  return out;
}

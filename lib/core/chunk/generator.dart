import 'dart:typed_data';
import '../models/world.dart';
import '../models/coord.dart';
import '../rng/seeded_rng.dart';

/// Generate chunk data: mines and hint numbers for a given chunk.
/// Returns a Map<Coord, int> where:
///   - value = -1 means mine
///   - value >= 0 means hint count (number of adjacent mines)
/// 
/// This function checks all 8 neighbouring chunks to calculate correct
/// hint numbers near chunk borders.
Map<Coord, int> generateChunk(World world, int chunkX, int chunkY) {
  final result = <Coord, int>{};
  final chunkSize = world.chunkSize;
  final worldSeed = world.seed.hashCode;
  
  // Generate mines for the current chunk
  final centerBitmap = generateChunkBitmap(
    worldSeed: worldSeed,
    chunkX: chunkX,
    chunkY: chunkY,
    chunkSize: chunkSize,
    minesPerChunk: world.minesPerChunk,
  );
  
  // Generate bitmaps for all 8 neighbouring chunks
  final neighbourBitmaps = <int, Uint8List>{};
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      if (dx == 0 && dy == 0) continue; // skip center
      final key = dy * 3 + dx; // -4 to 4, skipping 0
      neighbourBitmaps[key] = generateChunkBitmap(
        worldSeed: worldSeed,
        chunkX: chunkX + dx,
        chunkY: chunkY + dy,
        chunkSize: chunkSize,
        minesPerChunk: world.minesPerChunk,
      );
    }
  }
  
  // Helper to check if a tile is a mine
  bool isMine(int localX, int localY, int chunkDx, int chunkDy) {
    if (chunkDx == 0 && chunkDy == 0) {
      // Current chunk
      if (localX < 0 || localX >= chunkSize || localY < 0 || localY >= chunkSize) {
        return false;
      }
      return centerBitmap[localY * chunkSize + localX] == 1;
    } else {
      // Neighbour chunk
      final key = chunkDy * 3 + chunkDx;
      final bitmap = neighbourBitmaps[key];
      if (bitmap == null) return false;
      if (localX < 0 || localX >= chunkSize || localY < 0 || localY >= chunkSize) {
        return false;
      }
      return bitmap[localY * chunkSize + localX] == 1;
    }
  }
  
  // Process each tile in the current chunk
  for (int ly = 0; ly < chunkSize; ly++) {
    for (int lx = 0; lx < chunkSize; lx++) {
      final globalX = chunkX * chunkSize + lx;
      final globalY = chunkY * chunkSize + ly;
      final coord = Coord(globalX, globalY);
      
      // Check if this tile is a mine
      if (centerBitmap[ly * chunkSize + lx] == 1) {
        result[coord] = -1;
        continue;
      }
      
      // Count adjacent mines (including across chunk borders)
      int count = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          
          final adjLocalX = lx + dx;
          final adjLocalY = ly + dy;
          
          // Determine which chunk this adjacent tile belongs to
          int adjChunkDx = 0;
          int adjChunkDy = 0;
          int adjLocalXInChunk = adjLocalX;
          int adjLocalYInChunk = adjLocalY;
          
          if (adjLocalX < 0) {
            adjChunkDx = -1;
            adjLocalXInChunk = chunkSize + adjLocalX;
          } else if (adjLocalX >= chunkSize) {
            adjChunkDx = 1;
            adjLocalXInChunk = adjLocalX - chunkSize;
          }
          
          if (adjLocalY < 0) {
            adjChunkDy = -1;
            adjLocalYInChunk = chunkSize + adjLocalY;
          } else if (adjLocalY >= chunkSize) {
            adjChunkDy = 1;
            adjLocalYInChunk = adjLocalY - chunkSize;
          }
          
          if (isMine(adjLocalXInChunk, adjLocalYInChunk, adjChunkDx, adjChunkDy)) {
            count++;
          }
        }
      }
      
      result[coord] = count;
    }
  }
  
  return result;
}

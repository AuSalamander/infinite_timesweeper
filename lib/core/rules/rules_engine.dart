import 'dart:collection';
import '../models/coord.dart';
import '../models/tile_state.dart';
import '../models/world.dart';
import '../chunk/generator.dart';
import '../storage/storage.dart';

class RulesEngine {
  final World world;
  final TileStorage storage;
  final Map<String, Map<Coord, int>> _chunkCache = {};
  final List<String> _chunkCacheLRU = []; // LRU tracking
  static const int _maxCachedChunks = 200; // Limit cache size

  RulesEngine(this.world, this.storage);

  /// Check if chunk currently has active timeout (explosion within last 5 minutes)
  bool _hasActiveTimeout(int chunkX, int chunkY) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(minutes: 5));
    
    final chunkSize = world.chunkSize;
    final startX = chunkX * chunkSize;
    final startY = chunkY * chunkSize;
    
    // Check all tiles in the chunk
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

  /// Get chunk data with LRU caching
  Map<Coord, int> _getChunkData(int chunkX, int chunkY) {
    final key = '$chunkX,$chunkY';
    
    if (_chunkCache.containsKey(key)) {
      // Move to end of LRU list (most recently used)
      _chunkCacheLRU.remove(key);
      _chunkCacheLRU.add(key);
      return _chunkCache[key]!;
    }
    
    // Generate new chunk
    final chunkData = generateChunk(world, chunkX, chunkY);
    _chunkCache[key] = chunkData;
    _chunkCacheLRU.add(key);
    
    // Evict oldest if cache is full
    if (_chunkCacheLRU.length > _maxCachedChunks) {
      final oldestKey = _chunkCacheLRU.removeAt(0);
      _chunkCache.remove(oldestKey);
    }
    
    return chunkData;
  }

  /// Get hint number for a coordinate (requires tile to be generated)
  int _getHint(Coord coord) {
    final chunkCoord = coord.toChunk(world.chunkSize);
    final chunkData = _getChunkData(chunkCoord.chunkX, chunkCoord.chunkY);
    final value = chunkData[coord];
    if (value == null) return 0;
    return value == -1 ? -1 : value; // -1 = mine, >= 0 = hint
  }

  /// Check if coordinate is a mine
  bool _isMine(Coord coord) {
    return _getHint(coord) == -1;
  }

  /// Get all 8 neighbors of a coordinate
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

  /// Count flagged neighbors
  int _countFlaggedNeighbors(Coord coord) {
    int count = 0;
    for (final neighbor in _getNeighbors(coord)) {
      if (storage.get(neighbor).flag == TileFlag.flagged) {
        count++;
      }
    }
    return count;
  }

  /// Open a tile with flood-fill for hint 0 (iterative to avoid stack overflow)
  void _openTileFloodFill(Coord startCoord, DateTime timestamp, {void Function(Coord, DateTime)? onExplosion}) {
    final queue = Queue<Coord>()..add(startCoord);
    final visited = <Coord>{};
    const maxTilesToOpen = 10000; // Prevent infinite expansion

    while (queue.isNotEmpty && visited.length < maxTilesToOpen) {
      final coord = queue.removeFirst();
      
      // Skip if already visited
      if (visited.contains(coord)) continue;
      visited.add(coord);

      final state = storage.get(coord);
      // Don't open if already open or flagged
      if (state.flag != TileFlag.closed) continue;

      // Check if chunk has active timeout - prevent opening if so
      final chunkCoord = coord.toChunk(world.chunkSize);
      if (_hasActiveTimeout(chunkCoord.chunkX, chunkCoord.chunkY)) {
        continue;
      }

      final isMine = _isMine(coord);
      
      if (isMine) {
        // Explode
        storage.applyEvent(TileEvent(
          coord: coord,
          type: TileEventType.explode,
          timestamp: timestamp,
        ));
        // Notify about explosion
        onExplosion?.call(coord, timestamp);
      } else {
        // Open the tile
        storage.applyEvent(TileEvent(
          coord: coord,
          type: TileEventType.open,
          timestamp: timestamp,
        ));

        // If hint is 0, add neighbors to queue
        final hint = _getHint(coord);
        if (hint == 0) {
          for (final neighbor in _getNeighbors(coord)) {
            if (!visited.contains(neighbor)) {
              queue.add(neighbor);
            }
          }
        }
      }
    }
  }

  /// Open a tile at the given coordinate
  void openTile(Coord coord, {void Function(Coord, DateTime)? onExplosion}) {
    final timestamp = DateTime.now();
    final state = storage.get(coord);

    if (state.flag == TileFlag.flagged) {
      // Do nothing if flagged
      return;
    }

    if (state.flag == TileFlag.closed) {
      // Open closed tile with iterative flood-fill
      _openTileFloodFill(coord, timestamp, onExplosion: onExplosion);
    } else if (state.flag == TileFlag.open) {
      // Chord: if hint equals flagged neighbors, open all non-flagged neighbors
      final hint = _getHint(coord);
      if (hint > 0) {
        final flaggedCount = _countFlaggedNeighbors(coord);
        if (flaggedCount == hint) {
          // Open all non-flagged neighbors
          for (final neighbor in _getNeighbors(coord)) {
            final neighborState = storage.get(neighbor);
            if (neighborState.flag == TileFlag.closed) {
              _openTileFloodFill(neighbor, timestamp, onExplosion: onExplosion);
            }
          }
        }
      }
    }
  }

  /// Get hint number for a coordinate (for testing)
  int getHint(Coord coord) => _getHint(coord);

  /// Check if coordinate is a mine (for testing)
  bool isMine(Coord coord) => _isMine(coord);

  /// Flag or unflag a tile at the given coordinate
  void flagTile(Coord coord) {
    final state = storage.get(coord);

    if (state.flag == TileFlag.open) {
      // Do nothing if already opened
      return;
    }

    final timestamp = DateTime.now();
    
    if (state.flag == TileFlag.flagged) {
      // Unflag
      storage.applyEvent(TileEvent(
        coord: coord,
        type: TileEventType.unflag,
        timestamp: timestamp,
      ));
    } else {
      // Flag
      storage.applyEvent(TileEvent(
        coord: coord,
        type: TileEventType.flag,
        timestamp: timestamp,
      ));
    }
  }
}

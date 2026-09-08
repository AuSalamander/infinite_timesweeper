import 'dart:collection';
import '../models/coord.dart';
import '../models/tile_state.dart';
import '../models/world.dart';
import '../chunk/generator.dart';
import '../storage/storage.dart';

class RulesEngine {
  final World world;
  final TileStorage storage;
  // Chunk cache keyed by int (no per-lookup string allocs).
  // Dart Maps are insertion-ordered: remove + re-insert = O(1) MRU mark.
  final Map<int, Map<Coord, int>> _chunkCache = {};
  static const int _maxCachedChunks = 200; // Limit cache size

  // Counters for perf logging (cheap ints, read by FrameStats report).
  int cacheHits = 0;
  int cacheMisses = 0;

  RulesEngine(this.world, this.storage);

  static int chunkKey(int chunkX, int chunkY) =>
      ((chunkX & 0xffffffff) << 32) | (chunkY & 0xffffffff);

  /// Check if chunk currently has active timeout (explosion within last 5 minutes)
  /// Pass in [now]/[cutoff] so flood-fill can hoist DateTime.now() out of the loop.
  bool _hasActiveTimeout(int chunkX, int chunkY, DateTime now, DateTime cutoff) {
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

  /// Get chunk data with LRU caching (int keys, O(1) MRU refresh)
  Map<Coord, int> _getChunkData(int chunkX, int chunkY) {
    final key = chunkKey(chunkX, chunkY);

    final cached = _chunkCache[key];
    if (cached != null) {
      // Move to end (most recently used). Delete + re-insert is O(1).
      _chunkCache.remove(key);
      _chunkCache[key] = cached;
      cacheHits++;
      return cached;
    }

    // Generate new chunk
    final chunkData = generateChunk(world, chunkX, chunkY);
    cacheMisses++;
    _chunkCache[key] = chunkData;

    // Evict oldest if cache is full (first insertion-ordered key)
    if (_chunkCache.length > _maxCachedChunks) {
      _chunkCache.remove(_chunkCache.keys.first);
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
  void _openTileFloodFill(Coord startCoord, DateTime timestamp,
      {void Function(Coord, DateTime)? onExplosion,
      required DateTime cutoff,
      required Map<int, bool> timeoutMemo}) {
    final queue = Queue<Coord>()..add(startCoord);
    final visited = <Coord>{};
    const maxTilesToOpen = 10000; // Prevent infinite expansion

    bool isChunkLocked(int chunkX, int chunkY) {
      final key = chunkKey(chunkX, chunkY);
      return timeoutMemo.putIfAbsent(
          key, () => _hasActiveTimeout(chunkX, chunkY, timestamp, cutoff));
    }

    while (queue.isNotEmpty && visited.length < maxTilesToOpen) {
      final coord = queue.removeFirst();
      
      // Skip if already visited
      if (visited.contains(coord)) continue;
      visited.add(coord);

      final state = storage.get(coord);
      // Don't open if already open or flagged
      if (state.flag != TileFlag.closed) continue;

      // Check if chunk has active timeout - prevent opening if so
      // (memoized per chunk for this flood-fill; hints themselves are
      // immutable and served from _chunkCache, never recomputed per neighbor)
      final chunkCoord = coord.toChunk(world.chunkSize);
      if (isChunkLocked(chunkCoord.chunkX, chunkCoord.chunkY)) {
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
    // Hoisted: one clock read per gesture; shared by all flood-fills below.
    final timestamp = DateTime.now();
    final cutoff = timestamp.subtract(const Duration(minutes: 5));
    final timeoutMemo = <int, bool>{};
    final state = storage.get(coord);

    if (state.flag == TileFlag.flagged) {
      // Do nothing if flagged
      return;
    }

    if (state.flag == TileFlag.closed) {
      // Open closed tile with iterative flood-fill
      _openTileFloodFill(coord, timestamp,
          onExplosion: onExplosion, cutoff: cutoff, timeoutMemo: timeoutMemo);
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
              _openTileFloodFill(neighbor, timestamp,
                  onExplosion: onExplosion,
                  cutoff: cutoff,
                  timeoutMemo: timeoutMemo);
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

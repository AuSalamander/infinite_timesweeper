import 'dart:convert';
import 'dart:io';
import '../models/coord.dart';
import '../models/tile_state.dart';
import '../models/world.dart';

/// Event types for tile state changes
enum TileEventType {
  open,
  flag,
  unflag,
  explode,
}

/// Represents a single event that changes a tile's state
class TileEvent {
  final Coord coord;
  final TileEventType type;
  final DateTime timestamp;

  TileEvent({
    required this.coord,
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'coord': coord.toJson(),
        'type': type.toString().split('.').last,
        'timestamp': timestamp.toIso8601String(),
      };

  factory TileEvent.fromJson(Map<String, dynamic> j) => TileEvent(
        coord: Coord.fromJson(Map<String, int>.from(j['coord'])),
        type: TileEventType.values
            .firstWhere((e) => e.toString().split('.').last == j['type']),
        timestamp: DateTime.parse(j['timestamp']),
      );
}

/// Sparse storage for tile state changes
/// Only stores tiles that have been modified from their default state
class TileStorage {
  final Map<Coord, TileState> _tiles = {};
  World? _world;

  /// Get tile state at coordinate, returns default if not modified
  TileState get(Coord coord) {
    return _tiles[coord] ?? const TileState();
  }

  /// Apply an event to change tile state
  void applyEvent(TileEvent event) {
    final current = get(event.coord);

    TileState newState;
    switch (event.type) {
      case TileEventType.open:
        newState = current.copyWith(
          flag: TileFlag.open,
          openedAt: event.timestamp,
        );
        break;
      case TileEventType.flag:
        newState = current.copyWith(flag: TileFlag.flagged);
        break;
      case TileEventType.unflag:
        newState = current.copyWith(flag: TileFlag.closed);
        break;
      case TileEventType.explode:
        newState = current.copyWith(
          exploded: true,
          flag: TileFlag.open,
          openedAt: event.timestamp,
        );
        break;
    }

    _tiles[event.coord] = newState;
  }

  /// Get a snapshot of all modified tiles
  Map<Coord, TileState> snapshot() {
    return Map.from(_tiles);
  }

  /// Save storage to JSON file
  Future<void> saveToFile(String filePath, {World? world}) async {
    final data = {
      'world': world?.toJson(),
      'tiles': _tiles.map((coord, state) => MapEntry(
            '${coord.x},${coord.y}',
            state.toJson(),
          )),
    };

    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode(data));
  }

  /// Load storage from JSON file
  Future<World?> loadFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }

    final content = await file.readAsString();
    final data = json.decode(content) as Map<String, dynamic>;
    
    // Reset world before loading
    _world = null;
    
    // Load world data if present
    World? world;
    if (data['world'] != null) {
      world = World.fromJson(data['world'] as String);
      _world = world;
    }
    
    final tilesData = data['tiles'] as Map<String, dynamic>;

    _tiles.clear();
    for (final entry in tilesData.entries) {
      final coords = entry.key.split(',');
      final coord = Coord(int.parse(coords[0]), int.parse(coords[1]));
      final state = TileState.fromJson(entry.value as Map<String, dynamic>);
      _tiles[coord] = state;
    }
    
    return world;
  }

  /// Clear all stored tiles
  void clear() {
    _tiles.clear();
    _world = null;
  }

  /// Get number of modified tiles
  int get count => _tiles.length;
  
  /// Get the loaded world
  World? get world => _world;
}

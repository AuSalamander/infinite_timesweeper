import 'dart:convert';

class World {
  final String seed;
  final int chunkSize;
  final int minesPerChunk;
  final String name;
  final String formatVersion;

  World({
    required this.seed,
    required this.chunkSize,
    required this.minesPerChunk,
    required this.name,
    required this.formatVersion,
  });

  // Convert World object to JSON string
  String toJson() {
    return json.encode({
      'seed': seed,
      'chunkSize': chunkSize,
      'minesPerChunk': minesPerChunk,
      'name': name,
      'formatVersion': formatVersion,
    });
  }

  // Create World object from JSON string
  static World fromJson(String jsonString) {
    final Map<String, dynamic> data = json.decode(jsonString);

    // Required filds
    final requiredFields = [
      'seed',
      'chunkSize',
      'minesPerChunk',
      'name',
      'formatVersion',
    ];

    // Check required filds
    for (final field in requiredFields) {
      if (!data.containsKey(field) || data[field] == null) {
        throw ArgumentError('Missing required field: $field');
      }
    }

    return World(
      seed: data['seed'],
      chunkSize: data['chunkSize'],
      minesPerChunk: data['minesPerChunk'],
      name: data['name'],
      formatVersion: data['formatVersion'],
    );
  }
}

class Coord {
  final int x;
  final int y;
  const Coord(this.x, this.y);

  // Convert to chunk coordinates (floor division)
  ChunkCoord toChunk(int chunkSize) {
    final cx = (x >= 0) ? x ~/ chunkSize : -(((-x - 1) ~/ chunkSize) + 1);
    final lx = x - cx * chunkSize;
    final cy = (y >= 0) ? y ~/ chunkSize : -(((-y - 1) ~/ chunkSize) + 1);
    final ly = y - cy * chunkSize;
    return ChunkCoord(cx, cy, lx, ly);
  }

  Map<String,int> toJson() => {'x': x, 'y': y};
  factory Coord.fromJson(Map<String,int> j) => Coord(j['x']!, j['y']!);

  @override bool operator ==(Object o) => o is Coord && o.x == x && o.y == y;
  @override int get hashCode => x.hashCode ^ (y.hashCode << 1);
  @override String toString() => '$x,$y';
}

class ChunkCoord {
  final int chunkX, chunkY, localX, localY;
  ChunkCoord(this.chunkX, this.chunkY, this.localX, this.localY);
}

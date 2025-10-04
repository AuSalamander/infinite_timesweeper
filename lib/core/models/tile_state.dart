enum TileFlag { closed, open, flagged }

class TileState {
  final TileFlag flag;
  final bool exploded;
  final DateTime? openedAt;

  const TileState({
    this.flag = TileFlag.closed,
    this.exploded = false,
    this.openedAt,
  });

  TileState copyWith({TileFlag? flag, bool? exploded, DateTime? openedAt}) =>
      TileState(
        flag: flag ?? this.flag,
        exploded: exploded ?? this.exploded,
        openedAt: openedAt ?? this.openedAt,
      );

  Map<String, dynamic> toJson() => {
    'flag': flag.toString().split('.').last,
    'exploded': exploded,
    'openedAt': openedAt?.toIso8601String(),
  };

  factory TileState.fromJson(Map<String, dynamic> j) => TileState(
    flag: TileFlag.values.firstWhere((e) => e.toString().split('.').last == j['flag']),
    exploded: j['exploded'] ?? false,
    openedAt: j['openedAt'] != null ? DateTime.parse(j['openedAt']) : null,
  );
}

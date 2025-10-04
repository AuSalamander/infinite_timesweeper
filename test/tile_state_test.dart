import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_timesweeper/core/models/tile_state.dart';

void main() {
  group('TileState', () {
    test('Default state: closed, not exploded, openedAt is null', () {
      final state = TileState();
      expect(state.flag, TileFlag.closed);
      expect(state.exploded, false);
      expect(state.openedAt, isNull);
    });

    test('State copying: changing flag', () {
      final original = TileState();
      final updated = original.copyWith(flag: TileFlag.open);
      expect(updated.flag, TileFlag.open);
      expect(original.flag, TileFlag.closed);
    });

    test('State copying: changing exploded status', () {
      final original = TileState();
      final updated = original.copyWith(exploded: true);
      expect(updated.exploded, true);
      expect(original.exploded, false);
    });

    test('State copying: changing openedAt timestamp', () {
      final now = DateTime.now();
      final original = TileState();
      final updated = original.copyWith(openedAt: now);
      expect(updated.openedAt, now);
      expect(original.openedAt, isNull);
    });

    test('Serialization/deserialization via JSON', () {
      final now = DateTime(2023, 1, 1);
      final state = TileState(
        flag: TileFlag.flagged,
        exploded: true,
        openedAt: now,
      );

      // Serialize to JSON
      final json = state.toJson();
      expect(json['flag'], 'flagged');
      expect(json['exploded'], true);
      expect(json['openedAt'], '2023-01-01T00:00:00.000');

      // Deserialize from JSON
      final restored = TileState.fromJson(json);
      expect(restored.flag, TileFlag.flagged);
      expect(restored.exploded, true);
      expect(restored.openedAt, now);
    });

    test('Handling missing/nullable fields in JSON', () {
      final json = {
        'flag': 'open',
        'exploded': false,
        'openedAt': null,
      };
      final state = TileState.fromJson(json);
      expect(state.flag, TileFlag.open);
      expect(state.exploded, false);
      expect(state.openedAt, isNull);
    });
  });
}

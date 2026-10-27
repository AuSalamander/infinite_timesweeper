import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_timesweeper/core/perf/image_diff.dart';

void main() {
  group('compareRgba', () {
    test('reports identical images as equal', () {
      final pixels = Uint8List.fromList([1, 2, 3, 255, 4, 5, 6, 255]);
      final diff = compareRgba(pixels, pixels, width: 2, height: 1);
      expect(diff.differentPixels, 0);
      expect(diff.totalPixels, 2);
      expect(diff.maxChannelDelta, 0);
      expect(diff.diffRatio, 0);
    });

    test('ignores deltas within the channel tolerance', () {
      final actual = Uint8List.fromList([10, 20, 30, 255]);
      final expected = Uint8List.fromList([2, 28, 22, 247]);
      final diff = compareRgba(actual, expected, width: 1, height: 1);
      expect(diff.differentPixels, 0);
      expect(diff.maxChannelDelta, 8);
    });

    test('counts pixels above the channel tolerance', () {
      final actual = Uint8List.fromList([100, 0, 0, 255, 0, 0, 0, 255]);
      final expected = Uint8List.fromList([91, 0, 0, 255, 0, 8, 0, 255]);
      final diff = compareRgba(actual, expected, width: 2, height: 1);
      expect(diff.differentPixels, 1);
      expect(diff.maxChannelDelta, 9);
      expect(diff.diffRatio, 0.5);
    });

    test('treats alpha differences as visual differences', () {
      final actual = Uint8List.fromList([0, 0, 0, 255]);
      final expected = Uint8List.fromList([0, 0, 0, 0]);
      final diff = compareRgba(actual, expected, width: 1, height: 1);
      expect(diff.differentPixels, 1);
    });

    test('rejects malformed input', () {
      final pixels = Uint8List(4);
      expect(
        () => compareRgba(pixels, pixels, width: 0, height: 1),
        throwsArgumentError,
      );
      expect(
        () => compareRgba(pixels, pixels, width: 1, height: 0),
        throwsArgumentError,
      );
      expect(
        () => compareRgba(pixels, pixels, width: 2, height: 1),
        throwsArgumentError,
      );
      expect(
        () => compareRgba(
          pixels,
          pixels,
          width: 1,
          height: 1,
          channelTolerance: -1,
        ),
        throwsRangeError,
      );
      expect(
        () => compareRgba(
          pixels,
          pixels,
          width: 1,
          height: 1,
          channelTolerance: 256,
        ),
        throwsRangeError,
      );
    });
  });
}

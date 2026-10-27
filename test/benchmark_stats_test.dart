import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_timesweeper/core/perf/benchmark_stats.dart';

void main() {
  group('percentile', () {
    test('uses nearest rank without mutating input', () {
      final samples = [4.0, 1.0, 3.0, 2.0];
      expect(percentile(samples, 0), 1);
      expect(percentile(samples, 0.5), 2);
      expect(percentile(samples, 0.95), 4);
      expect(percentile(samples, 1), 4);
      expect(samples, [4.0, 1.0, 3.0, 2.0]);
    });

    test('handles one sample and rejects invalid input', () {
      expect(percentile([2.5], 0.99), 2.5);
      expect(() => percentile([], 0.5), throwsArgumentError);
      expect(() => percentile([1], -0.1), throwsRangeError);
      expect(() => percentile([1], 1.1), throwsRangeError);
    });
  });

  group('geometricMean', () {
    test('calculates a lower-is-better aggregate', () {
      expect(geometricMean([1, 4, 16]), closeTo(4, 0.000001));
    });

    test('rejects empty, zero, negative, and non-finite input', () {
      expect(() => geometricMean([]), throwsArgumentError);
      expect(() => geometricMean([1, 0]), throwsArgumentError);
      expect(() => geometricMean([-1]), throwsArgumentError);
      expect(() => geometricMean([double.infinity]), throwsArgumentError);
      expect(() => geometricMean([double.nan]), throwsArgumentError);
    });
  });
}

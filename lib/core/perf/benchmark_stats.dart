import 'dart:math' as math;

/// Nearest-rank percentile for a non-empty set of millisecond samples.
double percentile(List<double> samples, double percentile) {
  if (samples.isEmpty) {
    throw ArgumentError.value(samples, 'samples', 'must not be empty');
  }
  if (percentile < 0 || percentile > 1) {
    throw RangeError.range(percentile, 0, 1, 'percentile');
  }
  final sorted = List<double>.of(samples)..sort();
  final rank = (percentile * sorted.length).ceil();
  return sorted[math.max(0, rank - 1)];
}

/// Geometric mean of strictly positive values, used for the benchmark score.
double geometricMean(Iterable<double> values) {
  var count = 0;
  var logSum = 0.0;
  for (final value in values) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(
        value,
        'values',
        'all values must be finite and positive',
      );
    }
    logSum += math.log(value);
    count++;
  }
  if (count == 0) {
    throw ArgumentError.value(values, 'values', 'must not be empty');
  }
  return math.exp(logSum / count);
}

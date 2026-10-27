import 'dart:typed_data';

/// Result of comparing two RGBA images pixel by pixel.
class ImageDiff {
  const ImageDiff({
    required this.differentPixels,
    required this.totalPixels,
    required this.maxChannelDelta,
  });

  final int differentPixels;
  final int totalPixels;
  final int maxChannelDelta;

  double get diffRatio => totalPixels == 0 ? 0 : differentPixels / totalPixels;
}

/// Compares two RGBA byte buffers of [width] x [height].
///
/// A pixel counts as different when any colour channel (including alpha)
/// differs by more than [channelTolerance]. The strict greater-than comparison
/// makes a tolerance of 8 ignore deltas of 8 or less.
ImageDiff compareRgba(
  Uint8List actual,
  Uint8List expected, {
  required int width,
  required int height,
  int channelTolerance = 8,
}) {
  if (width <= 0) {
    throw ArgumentError.value(width, 'width', 'must be positive');
  }
  if (height <= 0) {
    throw ArgumentError.value(height, 'height', 'must be positive');
  }
  if (channelTolerance < 0 || channelTolerance > 255) {
    throw RangeError.range(channelTolerance, 0, 255, 'channelTolerance');
  }
  final expectedLength = width * height * 4;
  if (actual.length != expectedLength) {
    throw ArgumentError.value(
      actual.length,
      'actual',
      'expected $expectedLength bytes for $width x $height RGBA',
    );
  }
  if (expected.length != expectedLength) {
    throw ArgumentError.value(
      expected.length,
      'expected',
      'expected $expectedLength bytes for $width x $height RGBA',
    );
  }

  var differentPixels = 0;
  var maxChannelDelta = 0;
  for (var index = 0; index < expectedLength; index += 4) {
    var pixelDiffers = false;
    for (var channel = 0; channel < 4; channel++) {
      final delta = (actual[index + channel] - expected[index + channel]).abs();
      if (delta > maxChannelDelta) maxChannelDelta = delta;
      if (delta > channelTolerance) pixelDiffers = true;
    }
    if (pixelDiffers) differentPixels++;
  }
  return ImageDiff(
    differentPixels: differentPixels,
    totalPixels: width * height,
    maxChannelDelta: maxChannelDelta,
  );
}

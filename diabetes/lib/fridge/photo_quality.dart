import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Laplacian variance below this is a blurry photo. Measured with
/// [assessPhoto] on the eval photos (tool/scan_eval/bench/
/// quality_calibration_test.dart): the blurry webcam still scores 271 and
/// its clip frames 298–355, a sharp 24 MP phone photo 946. Only three
/// scenes were measured, so treat this as a first calibration.
const blurryBelow = 500.0;

/// More than this fraction of pixels with luma above [clippedLuma] is a photo
/// with bright light behind the subject. Measured: webcam 4.5%, phone 0.4%.
const overExposedAbove = 0.03;

/// Luma above which a pixel counts as clipped (blown out).
const clippedLuma = 245;

/// Longest side of the grayscale copy the metrics are computed on, so the
/// numbers don't depend on the camera's resolution.
const _assessSide = 512;

/// What [assessPhoto] measured on a photo.
class PhotoQuality {
  const PhotoQuality({required this.sharpness, required this.clippedFraction});

  /// Variance of the 4-neighbour Laplacian of the grayscale copy. Higher is
  /// sharper.
  final double sharpness;

  /// Fraction of pixels with luma above [clippedLuma].
  final double clippedFraction;

  bool get isBlurry => sharpness < blurryBelow;
  bool get isOverExposed => clippedFraction > overExposedAbove;

  /// Whether to warn the user before scanning this photo.
  bool get hasProblem => isBlurry || isOverExposed;
}

/// Measures [bytes] on a 512 px grayscale copy. A photo that can't be decoded
/// reports no problem: the scan itself will say so, and a warning must never
/// block it.
PhotoQuality assessPhoto(Uint8List bytes) =>
    _measure(bytes) ??
    const PhotoQuality(sharpness: double.infinity, clippedFraction: 0);

/// [assessPhoto] off the UI thread.
Future<PhotoQuality> assessPhotoAsync(Uint8List bytes) =>
    compute(assessPhoto, bytes);

/// Laplacian variance of [bytes] (0 when it can't be decoded), the same
/// sharpness [assessPhoto] reports. Used to rank burst frames.
double sharpnessScore(Uint8List bytes) => _measure(bytes)?.sharpness ?? 0;

PhotoQuality? _measure(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    return null;
  }
  if (decoded == null) return null;

  final longest = math.max(decoded.width, decoded.height);
  final small = longest > _assessSide
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? _assessSide : null,
          height: decoded.height > decoded.width ? _assessSide : null,
          interpolation: img.Interpolation.average,
        )
      : decoded;
  final w = small.width, h = small.height;

  final luma = Float64List(w * h);
  var clipped = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      luma[y * w + x] = l;
      if (l > clippedLuma) clipped++;
    }
  }

  var sharpness = 0.0;
  if (w >= 3 && h >= 3) {
    var sum = 0.0, sumSquares = 0.0;
    var n = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final lap =
            luma[i - 1] + luma[i + 1] + luma[i - w] + luma[i + w] - 4 * luma[i];
        sum += lap;
        sumSquares += lap * lap;
        n++;
      }
    }
    final mean = sum / n;
    sharpness = sumSquares / n - mean * mean;
  }
  return PhotoQuality(sharpness: sharpness, clippedFraction: clipped / (w * h));
}

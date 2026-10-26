import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Laplacian variance below this is a blurry photo. Measured with
/// [assessPhoto] on the eval photos (tool/scan_eval/bench/
/// quality_calibration_test.dart): the blurry webcam still scores 271 and
/// its clip frames 298–355, a sharp 24 MP phone photo 946. Only three
/// scenes were measured, so treat this as a first calibration.
const blurryBelow = 500.0;

/// Same cut-off for [assessPhotoWithCodec], whose 512 px copy is resampled by
/// the engine and scores lower. Measured with tool/scan_eval/bench/
/// quality_calibration_test.dart: blurry webcam still 107, its clip frames
/// 125-132, sharp 24 MP phone photo 759. The check takes 8-54 ms.
const engineBlurryBelow = 300.0;

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
  const PhotoQuality({
    required this.sharpness,
    required this.clippedFraction,
    this.blurryThreshold = blurryBelow,
  });

  /// Variance of the 4-neighbour Laplacian of the grayscale copy. Higher is
  /// sharper.
  final double sharpness;

  /// Fraction of pixels with luma above [clippedLuma].
  final double clippedFraction;

  /// The sharpness under which this measurement counts as blurry; depends on
  /// the path that measured it.
  final double blurryThreshold;

  bool get isBlurry => sharpness < blurryThreshold;
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

/// The quick check the UI uses: decodes a 512 px copy with the engine codec
/// (native on mobile, browser-native on web), so the full photo is never
/// materialised, then measures it. Falls back to [assessPhotoAsync] when the
/// codec throws.
Future<PhotoQuality> assessPhotoFast(Uint8List bytes) async {
  try {
    return await assessPhotoWithCodec(bytes);
  } on Object {
    return assessPhotoAsync(bytes);
  }
}

/// The engine-codec measurement behind [assessPhotoFast]. Throws when the
/// codec can't decode [bytes].
Future<PhotoQuality> assessPhotoWithCodec(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  int srcW, srcH;
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    srcW = descriptor.width;
    srcH = descriptor.height;
    descriptor.dispose();
  } finally {
    buffer.dispose();
  }
  final longest = math.max(srcW, srcH);
  final scale = longest > _assessSide ? _assessSide / longest : 1.0;
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: scale < 1 ? math.max(1, (srcW * scale).round()) : null,
    targetHeight: scale < 1 ? math.max(1, (srcH * scale).round()) : null,
  );
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw const FormatException('No pixel data');
      final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      return _measureLuma(
        _lumaOf(rgba, image.width * image.height),
        image.width,
        image.height,
        threshold: engineBlurryBelow,
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Float64List _lumaOf(Uint8List rgba, int pixels) {
  final luma = Float64List(pixels);
  for (var i = 0; i < pixels; i++) {
    luma[i] =
        0.299 * rgba[i * 4] + 0.587 * rgba[i * 4 + 1] + 0.114 * rgba[i * 4 + 2];
  }
  return luma;
}

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
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      luma[y * w + x] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    }
  }
  return _measureLuma(luma, w, h, threshold: blurryBelow);
}

/// Laplacian variance and clipped fraction of a [w] x [h] luma plane.
PhotoQuality _measureLuma(
  Float64List luma,
  int w,
  int h, {
  required double threshold,
}) {
  var clipped = 0;
  for (final l in luma) {
    if (l > clippedLuma) clipped++;
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
  return PhotoQuality(
    sharpness: sharpness,
    clippedFraction: clipped / (w * h),
    blurryThreshold: threshold,
  );
}

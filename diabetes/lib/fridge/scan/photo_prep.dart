import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'scan_models.dart';

/// Longest side of the JPEG sent to the model. Uploads never carry the full
/// original; the original stays in memory so later steps can crop tiles from
/// it at full detail.
const overviewMaxSide = 2048;
const overviewJpegQuality = 85;

/// Tilts at or below this many degrees are left alone: rotating resamples the
/// pixels, which costs more sharpness than a slight lean costs accuracy.
const straightenThresholdDegrees = 10.0;

/// A decoded photo: the pixels kept in memory plus the JPEG that gets sent.
class PreparedPhoto {
  const PreparedPhoto({
    required this.original,
    required this.overviewJpeg,
    required this.originalWidth,
    required this.originalHeight,
    required this.overviewWidth,
    required this.overviewHeight,
  });

  /// The decoded photo with its EXIF orientation applied. Smaller than
  /// [originalWidth] x [originalHeight] only if `maxKeptSide` capped it.
  final img.Image original;

  /// Longest side at most [overviewMaxSide], JPEG quality 85, never upscaled.
  final Uint8List overviewJpeg;

  /// Size of the photo as taken (orientation applied, before any cap).
  final int originalWidth;
  final int originalHeight;

  final int overviewWidth;
  final int overviewHeight;

  /// Overview pixels per kept-original pixel: 1 when the photo was already
  /// small enough, below 1 when it was shrunk. Never above 1.
  double get overviewScale => overviewWidth / original.width;
}

/// Decodes [bytes], applies the EXIF orientation, keeps the pixels and derives
/// the overview JPEG. [maxKeptSide] caps the longest side of the kept pixels
/// (0 = no cap) to bound memory on very large photos.
///
/// Throws [FormatException] if the bytes aren't a decodable image.
PreparedPhoto preparePhoto(Uint8List bytes, {int maxKeptSide = 0}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    // The decoders throw RangeError and friends on garbage, not null.
    decoded = null;
  }
  if (decoded == null) {
    throw const FormatException('Could not decode photo');
  }
  final oriented = img.bakeOrientation(decoded);
  return _prepareFromImage(oriented, maxKeptSide: maxKeptSide);
}

PreparedPhoto _prepareFromImage(
  img.Image oriented, {
  int maxKeptSide = 0,
  int? sourceWidth,
  int? sourceHeight,
}) {
  final kept = maxKeptSide > 0
      ? _fitLongestSide(oriented, maxKeptSide)
      : oriented;
  final overview = _fitLongestSide(kept, overviewMaxSide);
  return PreparedPhoto(
    original: kept,
    overviewJpeg: Uint8List.fromList(
      img.encodeJpg(overview, quality: overviewJpegQuality),
    ),
    originalWidth: sourceWidth ?? oriented.width,
    originalHeight: sourceHeight ?? oriented.height,
    overviewWidth: overview.width,
    overviewHeight: overview.height,
  );
}

/// Scales down so the longest side is at most [maxSide]; never scales up.
img.Image _fitLongestSide(img.Image image, int maxSide) {
  if (math.max(image.width, image.height) <= maxSide) return image;
  return img.copyResize(
    image,
    width: image.width >= image.height ? maxSide : null,
    height: image.height > image.width ? maxSide : null,
    interpolation: img.Interpolation.average,
  );
}

class _PrepareRequest {
  const _PrepareRequest(this.bytes, this.maxKeptSide);

  final Uint8List bytes;
  final int maxKeptSide;
}

PreparedPhoto _prepareInIsolate(_PrepareRequest request) =>
    preparePhoto(request.bytes, maxKeptSide: request.maxKeptSide);

/// [preparePhoto] off the UI isolate, so decoding a 12–24 MP photo with the
/// pure-Dart decoder doesn't freeze the app. On web `compute` runs inline.
Future<PreparedPhoto> preparePhotoAsync(
  Uint8List bytes, {
  int maxKeptSide = 0,
}) => compute(_prepareInIsolate, _PrepareRequest(bytes, maxKeptSide));

/// Rotates [image] clockwise by [clockwiseDegrees] (bicubic) on a canvas
/// grown to hold the whole rotated photo; the corners it leaves are empty.
img.Image rotateForTilt(img.Image image, double clockwiseDegrees) {
  return img.copyRotate(
    image,
    angle: clockwiseDegrees,
    interpolation: img.Interpolation.cubic,
  );
}

/// Maps a `[ymin, xmin, ymax, xmax]` box on a 0–1000 grid over a [width] x
/// [height] image into the 0–1000 grid of the same image after
/// [rotateForTilt] by [clockwiseDegrees]: the axis-aligned bounds of the four
/// rotated corners.
List<int> rotateBox(
  List<int> box2d,
  double clockwiseDegrees,
  int width,
  int height,
) {
  final radians = clockwiseDegrees * math.pi / 180;
  final cosA = math.cos(radians);
  final sinA = math.sin(radians);
  // Snap the exact quarter turns so 90° doesn't leave 1e-14 of error behind.
  final ca = cosA.abs() < 1e-12 ? 0.0 : cosA;
  final sa = sinA.abs() < 1e-12 ? 0.0 : sinA;
  final newWidth = width * ca.abs() + height * sa.abs();
  final newHeight = width * sa.abs() + height * ca.abs();

  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final y in [box2d[0], box2d[2]]) {
    for (final x in [box2d[1], box2d[3]]) {
      final dx = x / 1000 * width - width / 2;
      final dy = y / 1000 * height - height / 2;
      final rx = dx * ca - dy * sa + newWidth / 2;
      final ry = dx * sa + dy * ca + newHeight / 2;
      minX = math.min(minX, rx);
      maxX = math.max(maxX, rx);
      minY = math.min(minY, ry);
      maxY = math.max(maxY, ry);
    }
  }
  int grid(double value, double size) =>
      (value / size * 1000).round().clamp(0, 1000);
  return [
    grid(minY, newHeight),
    grid(minX, newWidth),
    grid(maxY, newHeight),
    grid(maxX, newWidth),
  ];
}

/// The outcome of [straightenIfTilted].
class StraightenedPhoto {
  const StraightenedPhoto({
    required this.photo,
    required this.items,
    required this.rotated,
  });

  /// The input photo if it wasn't rotated, else the rotated one.
  final PreparedPhoto photo;

  /// The input items, with boxes moved into the rotated photo when [rotated].
  final List<ScannedItem> items;
  final bool rotated;
}

/// Levels the kept original when the scan reported a tilt of more than
/// [straightenThresholdDegrees] either way, and moves [items]' boxes with it.
/// This only transforms pixels and boxes already in hand; it never calls the
/// model again.
StraightenedPhoto straightenIfTilted(
  PreparedPhoto photo,
  double tiltDegrees, {
  List<ScannedItem> items = const [],
}) {
  if (!tiltDegrees.isFinite || tiltDegrees.abs() <= straightenThresholdDegrees) {
    return StraightenedPhoto(photo: photo, items: items, rotated: false);
  }
  final source = photo.original;
  final rotated = rotateForTilt(source, tiltDegrees);
  final straightened = _prepareFromImage(
    rotated,
    sourceWidth: photo.originalWidth,
    sourceHeight: photo.originalHeight,
  );
  return StraightenedPhoto(
    photo: straightened,
    items: [
      for (final item in items)
        item.box2d == null
            ? item
            : item.copyWith(
                box2d: rotateBox(
                  item.box2d!,
                  tiltDegrees,
                  source.width,
                  source.height,
                ),
              ),
    ],
    rotated: true,
  );
}

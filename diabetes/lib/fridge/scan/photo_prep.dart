import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'scan_models.dart';

/// Longest side of the JPEG sent to the model. Uploads never carry the full
/// original; the original stays in memory so later steps can crop tiles from
/// it at full detail.
const overviewMaxSide = 2048;
const overviewJpegQuality = 85;

/// Longest side of the pixels [preparePhotoAsync] keeps by default. The kept
/// original only feeds tile crops, and a 2x2 grid of a 4096 px photo still
/// gives tiles of about 2300 px, more than the 2048 px upload.
const defaultMaxKeptSide = 4096;

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

/// Like [preparePhoto], but decodes with the engine's image codec (native on
/// mobile, browser-native on web), which is several times faster than the
/// pure-Dart decoder and, with a target size, never materialises the full
/// 24 MP bitmap. Falls back to [preparePhoto] in an isolate (inline on web) if
/// the codec path throws, e.g. for formats the engine can't decode.
///
/// [maxKeptSide] caps the longest side of the kept pixels (0 = no cap).
Future<PreparedPhoto> preparePhotoAsync(
  Uint8List bytes, {
  int maxKeptSide = defaultMaxKeptSide,
}) async {
  try {
    return await _prepareWithCodec(bytes, maxKeptSide);
  } on Object {
    return compute(_prepareInIsolate, _PrepareRequest(bytes, maxKeptSide));
  }
}

/// The engine codec's EXIF handling isn't documented, so [_engineAppliesExif]
/// checks it once with a tiny orientation-6 JPEG and we bake in Dart only if
/// the codec didn't rotate.
Future<PreparedPhoto> _prepareWithCodec(Uint8List bytes, int maxKeptSide) async {
  final (srcW, srcH) = await _intrinsicSize(bytes);
  final srcLong = math.max(srcW, srcH);

  final orientation = _exifOrientation(bytes);
  final needsBake = orientation > 1 && !await _engineAppliesExif();

  final keptLong = maxKeptSide > 0 ? math.min(srcLong, maxKeptSide) : srcLong;
  final kept = await _decodeScaled(bytes, srcW, srcH, keptLong / srcLong);

  final keptImage = img.Image.fromBytes(
    width: kept.width,
    height: kept.height,
    bytes: kept.rgba.buffer,
    bytesOffset: kept.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );

  if (needsBake) {
    // Rare: the engine ignores EXIF. Bake the capped pixels and derive the
    // overview in Dart; the kept image is at most maxKeptSide so this is cheap.
    keptImage.exif.imageIfd.orientation = orientation;
    final baked = img.bakeOrientation(keptImage);
    final swapped = _swapsSides(orientation);
    return _prepareFromImage(
      baked,
      sourceWidth: swapped ? srcH : srcW,
      sourceHeight: swapped ? srcW : srcH,
    );
  }

  // Size as taken, orientation applied: the engine already rotated, so it is
  // the intrinsic size with the sides swapped when the decode came out swapped.
  final decodedSwapped =
      srcW != srcH && (kept.width > kept.height) != (srcW > srcH);
  final originalWidth = decodedSwapped ? srcH : srcW;
  final originalHeight = decodedSwapped ? srcW : srcH;

  final overviewLong = math.min(keptLong, overviewMaxSide);
  final _Decoded overview = overviewLong == keptLong
      ? kept
      : await _decodeScaled(bytes, srcW, srcH, overviewLong / srcLong);

  final jpeg = await compute(
    _encodeOverview,
    _EncodeRequest(overview.rgba, overview.width, overview.height),
  );
  return PreparedPhoto(
    original: keptImage,
    overviewJpeg: jpeg,
    originalWidth: originalWidth,
    originalHeight: originalHeight,
    overviewWidth: overview.width,
    overviewHeight: overview.height,
  );
}

class _Decoded {
  const _Decoded(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

/// Width and height from the container header, without decoding pixels.
Future<(int, int)> _intrinsicSize(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      return (descriptor.width, descriptor.height);
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

/// Decodes at [scale] (<= 1) of the intrinsic size; the codec downsamples
/// while decoding. Throws if the result's aspect ratio doesn't match the
/// intrinsic one (an engine that applied the target before rotating), so the
/// caller falls back to the pure-Dart path instead of using a distorted photo.
Future<_Decoded> _decodeScaled(
  Uint8List bytes,
  int srcW,
  int srcH,
  double scale,
) async {
  final scaled = scale < 1;
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: scaled ? math.max(1, (srcW * scale).round()) : null,
    targetHeight: scaled ? math.max(1, (srcH * scale).round()) : null,
  );
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw const FormatException('No pixel data');
      final ratio = image.width / image.height;
      final srcRatio = srcW / srcH;
      if ((ratio / srcRatio - 1).abs() > 0.03 &&
          (ratio * srcRatio - 1).abs() > 0.03) {
        throw const FormatException('Codec distorted the photo');
      }
      return _Decoded(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        image.width,
        image.height,
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// EXIF orientation (1-8) of a JPEG, 1 when absent or not a JPEG.
int _exifOrientation(Uint8List bytes) {
  try {
    return img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1;
  } on Object {
    return 1;
  }
}

bool _swapsSides(int orientation) => orientation >= 5 && orientation <= 8;

Future<bool>? _engineAppliesExifProbe;

/// Whether the engine codec returns pixels already rotated by EXIF. Decides
/// once per process by decoding a 2x1 JPEG tagged orientation 6: upright
/// output is 1x2.
Future<bool> _engineAppliesExif() => _engineAppliesExifProbe ??= () async {
  final probe = img.Image(width: 2, height: 1)
    ..exif.imageIfd.orientation = 6;
  final codec = await ui.instantiateImageCodec(
    Uint8List.fromList(img.encodeJpg(probe)),
  );
  try {
    final frame = await codec.getNextFrame();
    final applied = frame.image.height > frame.image.width;
    frame.image.dispose();
    return applied;
  } finally {
    codec.dispose();
  }
}();

class _EncodeRequest {
  const _EncodeRequest(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

Uint8List _encodeOverview(_EncodeRequest request) {
  final image = img.Image.fromBytes(
    width: request.width,
    height: request.height,
    bytes: request.rgba.buffer,
    bytesOffset: request.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(
    img.encodeJpg(image, quality: overviewJpegQuality),
  );
}

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

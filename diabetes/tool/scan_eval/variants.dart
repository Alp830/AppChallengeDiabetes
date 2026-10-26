import 'dart:math' as math;
import 'dart:typed_data';

import 'package:diabetes/fridge/scan/fridge_scan_service.dart';
import 'package:image/image.dart' as img;

import 'scorer.dart';
import 'variants_v2.dart';
import 'variants_v3.dart';

/// What one variant run produced.
class VariantResult {
  const VariantResult({
    required this.items,
    required this.usage,
    this.calls,
    this.callTimings,
    this.perCall,
  });

  final List<ScanOutputItem> items;
  final FridgeScanUsage usage;

  /// Model calls made and how long each ran; null for single-call variants.
  final int? calls;
  final List<Duration>? callTimings;

  /// Each call's items before merging, boxes in photo space, so a merge
  /// change can be re-tested offline: {id, items: [{name, alternatives,
  /// confidence, box, location}]}. Null when the variant doesn't keep them.
  final List<Map<String, Object?>>? perCall;
}

/// A scan pipeline: raw photo bytes in, scan output and token usage out.
/// Makes exactly one model call, with no retry loop, so a failure shows up
/// as a failed run instead of being hidden by a retry.
typedef ScanVariant =
    Future<VariantResult> Function(Uint8List photoBytes, {required String apiKey});

/// Add v2/v3 here, keyed by the SCAN_VARIANT value.
final Map<String, ScanVariant> scanVariants = {
  'baseline': runBaseline,
  ...v2Variants,
  ...v3Variants,
};

/// The gallery picker's limits in lib/main.dart (`_uploadPhoto`).
const baselineMaxSide = 2048;
const baselineJpegQuality = 85;

/// Today's pipeline: shrink to 2048 px max side at JPEG quality 85 (what
/// image_picker does for a gallery photo), then call the app's scan service.
Future<VariantResult> runBaseline(
  Uint8List photoBytes, {
  required String apiKey,
}) async {
  final jpeg = resizeLikeGalleryPicker(photoBytes);
  final result = await FridgePhotoFoodAgent.detectFoodsWithUsage(
    jpeg,
    apiKey: apiKey,
  );
  return VariantResult(
    items: [for (final item in result.items) ScanOutputItem(item.name)],
    usage: result.usage,
  );
}

/// Applies EXIF rotation, scales down (never up) so the longer side is at
/// most [baselineMaxSide], and re-encodes as JPEG.
Uint8List resizeLikeGalleryPicker(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Could not decode photo');
  }
  var image = img.bakeOrientation(decoded);
  final longest = math.max(image.width, image.height);
  if (longest > baselineMaxSide) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? baselineMaxSide : null,
      height: image.height > image.width ? baselineMaxSide : null,
      interpolation: img.Interpolation.average,
    );
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: baselineJpegQuality));
}

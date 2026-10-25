import 'dart:typed_data';

import 'package:diabetes/fridge/scan/fridge_scan_service.dart';
import 'package:diabetes/fridge/scan/photo_prep.dart';

import 'scorer.dart';
import 'variants.dart';

/// Same shape as [ScanVariant]; kept as its own name so the v2 registry reads
/// clearly. Makes exactly one model call, with no retry loop.
typedef ScanVariantV2 =
    Future<VariantResult> Function(Uint8List photoBytes, {required String apiKey});

/// Scan v2 pipelines, keyed by the SCAN_VARIANT value. The root registers
/// this map in variants.dart.
final Map<String, ScanVariantV2> v2Variants = {
  'v2-high': (photoBytes, {required apiKey}) =>
      runV2(photoBytes, apiKey: apiKey),
  'v2-ultra': (photoBytes, {required apiKey}) =>
      runV2(photoBytes, apiKey: apiKey, perPartUltraHigh: true),
  'v2-medium': (photoBytes, {required apiKey}) =>
      runV2(photoBytes, apiKey: apiKey, thinkingLevel: 'medium'),
};

/// The app's v2 path: derive the 2048 px overview from the original photo,
/// scan it, and report each item with its confidence and alternatives.
Future<VariantResult> runV2(
  Uint8List photoBytes, {
  required String apiKey,
  String mediaResolution = 'MEDIA_RESOLUTION_HIGH',
  bool perPartUltraHigh = false,
  String thinkingLevel = 'low',
}) async {
  final photo = preparePhoto(photoBytes);
  final response = await FridgeScanService.scanV2(
    photo.overviewJpeg,
    apiKey: apiKey,
    mediaResolution: mediaResolution,
    perPartUltraHigh: perPartUltraHigh,
    thinkingLevel: thinkingLevel,
  );
  return VariantResult(
    items: [
      for (final item in response.items)
        ScanOutputItem(
          item.name,
          alternatives: item.alternatives,
          confidence: item.confidence.label,
        ),
    ],
    usage: response.usage,
  );
}

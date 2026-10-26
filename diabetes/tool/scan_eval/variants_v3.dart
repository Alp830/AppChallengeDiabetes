import 'dart:typed_data';

import 'package:diabetes/fridge/scan/fridge_scan_pipeline.dart';
import 'package:diabetes/fridge/scan/photo_prep.dart';
import 'package:diabetes/fridge/scan/scan_models.dart';

import 'scorer.dart';
import 'variants.dart';

/// Multi-call scan pipelines, keyed by the SCAN_VARIANT value. All lean, low
/// thinking and no deadline, so accuracy is measured on every tile; the
/// latency is recorded by the eval. Registered in variants.dart.
final Map<String, ScanVariant> v3Variants = {
  'v3-grid': (photoBytes, {required apiKey}) =>
      runV3(photoBytes, apiKey: apiKey, plan: ScanPlan.grid),
  'v3-grid-overview': (photoBytes, {required apiKey}) =>
      runV3(photoBytes, apiKey: apiKey, plan: ScanPlan.gridPlusOverview),
  'v3-zones': (photoBytes, {required apiKey}) =>
      runV3(photoBytes, apiKey: apiKey, plan: ScanPlan.zones),
  'v3-zoom': (photoBytes, {required apiKey}) =>
      runV3(photoBytes, apiKey: apiKey, plan: ScanPlan.zoom),
  'v3-grid-zoom': (photoBytes, {required apiKey}) =>
      runV3(photoBytes, apiKey: apiKey, plan: ScanPlan.gridPlusZoom),
};

/// The app's multi-call path: prepare the photo, run [plan], and report each
/// item with its confidence and alternatives. Usage is summed over the calls.
Future<VariantResult> runV3(
  Uint8List photoBytes, {
  required String apiKey,
  required ScanPlan plan,
  String thinkingLevel = 'low',
}) async {
  final photo = preparePhoto(photoBytes);
  final result = await FridgeScanPipeline.scan(
    photo,
    plan: plan,
    style: ScanStyle.lean,
    thinkingLevel: thinkingLevel,
    apiKey: apiKey,
  );
  return VariantResult(
    items: [
      for (final item in result.items)
        ScanOutputItem(
          item.name,
          alternatives: item.alternatives,
          confidence: item.confidence.label,
        ),
    ],
    usage: result.usage,
    calls: result.calls,
    callTimings: result.callTimings,
  );
}

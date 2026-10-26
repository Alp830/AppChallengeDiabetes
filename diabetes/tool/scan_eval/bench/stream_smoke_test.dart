// Live smoke test of the app's streaming scan: time to first item and total.
//   flutter test tool/scan_eval/bench/stream_smoke_test.dart \
//     --dart-define=GEMINI_API_KEY=... [--dart-define=SCAN_PHOTO=clear_phone.jpg]
import 'dart:io';

import 'package:diabetes/fridge/scan/fridge_scan_pipeline.dart';
import 'package:diabetes/fridge/scan/photo_prep.dart';
import 'package:diabetes/fridge/scan/scan_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _apiKey = String.fromEnvironment('GEMINI_API_KEY');
const _photo = String.fromEnvironment(
  'SCAN_PHOTO',
  defaultValue: 'blurry_webcam.jpg',
);

void main() {
  test(
    'streaming scan of $_photo',
    () async {
      HttpOverrides.global = null;
      final bytes = File('tool/scan_eval/photos/$_photo').readAsBytesSync();
      final photo = preparePhoto(bytes, maxKeptSide: 4096);
      final watch = Stopwatch()..start();
      Duration? first;
      var updates = 0;
      final result = await FridgeScanPipeline.scan(
        photo,
        plan: ScanPlan.grid,
        style: ScanStyle.lean,
        apiKey: _apiKey,
        onProgress: (p) {
          updates++;
          if (p.itemsSoFar > 0) first ??= watch.elapsed;
        },
      );
      // ignore: avoid_print
      print('first item ${first?.inMilliseconds} ms, total '
          '${watch.elapsedMilliseconds} ms, $updates updates, '
          '${result.calls} calls, ${result.items.length} items, '
          'usage ${result.usage.promptTokenCount}/'
          '${result.usage.candidatesTokenCount}');
      expect(result.items, isNotEmpty);
      expect(first, isNotNull);
    },
    skip: _apiKey.isEmpty ? 'GEMINI_API_KEY not set' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

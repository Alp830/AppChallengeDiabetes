// Prints the app's photo-quality scores on the eval photos and clip frames,
// for both paths: pure Dart (assessPhoto) and the engine codec
// (assessPhotoWithCodec, what the app uses).
//   flutter test tool/scan_eval/bench/quality_calibration_test.dart
import 'dart:io';

import 'package:diabetes/fridge/photo_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quality scores', (tester) async {
    final dir = Directory('tool/scan_eval/photos');
    if (!dir.existsSync()) return;
    final files = [
      File('${dir.path}/blurry_webcam.jpg'),
      File('${dir.path}/clear_phone.jpg'),
      ...Directory('${dir.path}/clip_frames').listSync().whereType<File>(),
    ]..removeWhere((f) => !f.existsSync());
    await tester.runAsync(() async {
      for (final f in files) {
        final bytes = f.readAsBytesSync();
        final dart = assessPhoto(bytes);
        final watch = Stopwatch()..start();
        final codec = await assessPhotoWithCodec(bytes);
        // ignore: avoid_print
        print('${f.uri.pathSegments.last}: dart ${dart.sharpness.round()} '
            '| codec ${codec.sharpness.round()} in ${watch.elapsedMilliseconds} ms, '
            'clipped ${(codec.clippedFraction * 100).toStringAsFixed(1)}%, '
            'blurry ${codec.isBlurry}');
      }
    });
  });
}

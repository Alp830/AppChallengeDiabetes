// Prints the app's photo-quality scores on the eval photos and clip frames.
//   flutter test tool/scan_eval/bench/quality_calibration_test.dart
import 'dart:io';

import 'package:diabetes/fridge/photo_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quality scores', () {
    final dir = Directory('tool/scan_eval/photos');
    if (!dir.existsSync()) return;
    final files = [
      File('${dir.path}/blurry_webcam.jpg'),
      File('${dir.path}/clear_phone.jpg'),
      ...Directory('${dir.path}/clip_frames').listSync().whereType<File>(),
    ]..removeWhere((f) => !f.existsSync());
    for (final f in files) {
      final q = assessPhoto(f.readAsBytesSync());
      // ignore: avoid_print
      print('${f.uri.pathSegments.last}: sharpness '
          '${q.sharpness.toStringAsFixed(1)}, clipped '
          '${(q.clippedFraction * 100).toStringAsFixed(1)}%, '
          'blurry ${q.isBlurry}, overExposed ${q.isOverExposed}');
    }
  });
}

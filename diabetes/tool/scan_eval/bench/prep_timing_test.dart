// Times photo prep on the eval photos (Dart VM; web JS is typically slower).
//   flutter test tool/scan_eval/bench/prep_timing_test.dart
import 'dart:io';

import 'package:diabetes/fridge/scan/photo_prep.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final name in ['clear_phone.jpg', 'blurry_webcam.jpg']) {
    test('prep $name', () {
      final file = File('tool/scan_eval/photos/$name');
      if (!file.existsSync()) return;
      final bytes = file.readAsBytesSync();
      for (final cap in [0, 4096]) {
        final watch = Stopwatch()..start();
        final photo = preparePhoto(bytes, maxKeptSide: cap);
        // ignore: avoid_print
        print('$name cap=$cap: ${watch.elapsedMilliseconds} ms, kept '
            '${photo.original.width}x${photo.original.height}, overview '
            '${photo.overviewWidth}x${photo.overviewHeight}, '
            '${photo.overviewJpeg.length ~/ 1024} KB');
      }
    });
  }
}

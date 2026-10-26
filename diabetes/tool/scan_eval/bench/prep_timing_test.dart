// Times photo prep on the eval photos: the pure-Dart decoder against the
// engine codec path. Web JS is typically slower than the Dart VM.
//   flutter test tool/scan_eval/bench/prep_timing_test.dart
import 'dart:io';

import 'package:diabetes/fridge/scan/photo_prep.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final name in ['clear_phone.jpg', 'blurry_webcam.jpg']) {
    testWidgets('prep $name', (tester) async {
      final file = File('tool/scan_eval/photos/$name');
      if (!file.existsSync()) return;
      final bytes = file.readAsBytesSync();

      void report(String label, int ms, PreparedPhoto photo) {
        // ignore: avoid_print
        print('$name $label: $ms ms, kept '
            '${photo.original.width}x${photo.original.height}, overview '
            '${photo.overviewWidth}x${photo.overviewHeight}, '
            '${photo.overviewJpeg.length ~/ 1024} KB');
      }

      for (final cap in [0, 4096]) {
        final watch = Stopwatch()..start();
        final photo = preparePhoto(bytes, maxKeptSide: cap);
        report('pure-Dart cap=$cap', watch.elapsedMilliseconds, photo);
      }

      await tester.runAsync(() async {
        // The first call also runs the one-off EXIF probe; time a warm run too.
        for (final run in ['cold', 'warm']) {
          for (final cap in [0, 4096]) {
            final watch = Stopwatch()..start();
            final photo = await preparePhotoAsync(bytes, maxKeptSide: cap);
            report('codec $run cap=$cap', watch.elapsedMilliseconds, photo);
          }
        }
      });
    });
  }
}

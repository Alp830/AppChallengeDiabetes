import 'dart:typed_data';

import 'package:camera/camera.dart' show XFile;
import 'package:diabetes/fridge/burst_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _frame({required bool sharp}) {
  final image = img.Image(width: 128, height: 128);
  for (var y = 0; y < 128; y++) {
    for (var x = 0; x < 128; x++) {
      final v = ((x ~/ 8) + (y ~/ 8)).isEven ? 60 : 180;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  final out = sharp ? image : img.gaussianBlur(image, radius: 6);
  return Uint8List.fromList(img.encodePng(out));
}

void main() {
  setUp(() => BurstCapture.tooSlow = false);
  tearDown(() => BurstCapture.tooSlow = false);

  test('keeps the sharpest of the frames', () async {
    final sharp = _frame(sharp: true);
    final blurry = _frame(sharp: false);
    final sequence = [blurry, blurry, sharp, blurry];
    var taken = 0;

    final result = await captureSharpest(
      () async => XFile.fromData(sequence[taken++]),
    );

    expect(taken, 4);
    expect(result.bytes, sharp);
    expect(result.scores, hasLength(4));
    expect(result.scores[2], greaterThan(result.scores[0]));
    expect(result.scores[2], greaterThan(result.scores[3]));
    expect(result.frames, 4);
  });

  test('stops once the budget has passed but keeps what it has', () async {
    var now = Duration.zero;
    var taken = 0;
    final frame = _frame(sharp: true);

    final result = await captureSharpest(
      () async {
        taken++;
        now += const Duration(milliseconds: 400);
        return XFile.fromData(frame);
      },
      clock: () => now,
    );

    // 400 ms, 800 ms (not past the budget yet), 1200 ms, then it stops.
    expect(taken, 3);
    expect(result.scores, hasLength(3));
    expect(result.elapsed, const Duration(milliseconds: 1200));
  });

  test('always keeps one frame, even when the budget is zero', () async {
    var taken = 0;
    final frame = _frame(sharp: true);

    final result = await captureSharpest(
      () async {
        taken++;
        return XFile.fromData(frame);
      },
      budget: Duration.zero,
      clock: () => Duration(milliseconds: taken * 10),
    );

    expect(taken, 1);
    expect(result.bytes, frame);
  });

  test('a slow first frame turns bursts off for the session', () async {
    var now = Duration.zero;
    var taken = 0;
    final frame = _frame(sharp: true);
    Future<XFile> take() async {
      taken++;
      now += const Duration(milliseconds: 2000);
      return XFile.fromData(frame);
    }

    final first = await captureSharpest(take, clock: () => now);
    expect(taken, 1);
    expect(first.bytes, frame);
    expect(first.scores, isEmpty);
    expect(BurstCapture.tooSlow, isTrue);

    taken = 0;
    final second = await captureSharpest(take, clock: () => now);
    expect(taken, 1);
    expect(second.bytes, frame);
  });

  test('frames: 1 takes a single frame', () async {
    var taken = 0;
    final frame = _frame(sharp: true);

    final result = await captureSharpest(() async {
      taken++;
      return XFile.fromData(frame);
    }, frames: 1);

    expect(taken, 1);
    expect(result.bytes, frame);
    expect(BurstCapture.tooSlow, isFalse);
  });
}

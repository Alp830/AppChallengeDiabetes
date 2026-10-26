import 'dart:typed_data';

import 'package:diabetes/fridge/photo_quality.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 8 px squares of two mid greys, so nothing is blown out.
img.Image _checkerboard() {
  final image = img.Image(width: 256, height: 256);
  for (var y = 0; y < 256; y++) {
    for (var x = 0; x < 256; x++) {
      final v = ((x ~/ 8) + (y ~/ 8)).isEven ? 60 : 180;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

Uint8List _png(img.Image image) => Uint8List.fromList(img.encodePng(image));

void main() {
  test('a sharp checkerboard is not blurry or over-exposed', () {
    final quality = assessPhoto(_png(_checkerboard()));

    expect(quality.sharpness, greaterThan(blurryBelow));
    expect(quality.isBlurry, isFalse);
    expect(quality.isOverExposed, isFalse);
    expect(quality.hasProblem, isFalse);
  });

  test('a blurred copy is blurry', () {
    final blurred = img.gaussianBlur(_checkerboard(), radius: 8);
    final quality = assessPhoto(_png(blurred));

    expect(quality.sharpness, lessThan(blurryBelow));
    expect(quality.isBlurry, isTrue);
    expect(quality.isOverExposed, isFalse);
  });

  test('an over-bright image trips the exposure check', () {
    final bright = img.Image(width: 128, height: 128)
      ..clear(img.ColorRgb8(252, 252, 252));
    final quality = assessPhoto(_png(bright));

    expect(quality.clippedFraction, closeTo(1, 0.001));
    expect(quality.isOverExposed, isTrue);
  });

  test('a small bright patch under the limit is fine', () {
    final image = _checkerboard();
    // About 1% of the pixels.
    for (var y = 0; y < 26; y++) {
      for (var x = 0; x < 26; x++) {
        image.setPixelRgb(x, y, 255, 255, 255);
      }
    }
    final quality = assessPhoto(_png(image));

    expect(quality.clippedFraction, lessThan(overExposedAbove));
    expect(quality.isOverExposed, isFalse);
  });

  test('bytes that are not an image report no problem', () {
    final quality = assessPhoto(Uint8List.fromList(const [1, 2, 3]));

    expect(quality.hasProblem, isFalse);
    expect(sharpnessScore(Uint8List.fromList(const [1, 2, 3])), 0);
  });

  test('sharpnessScore matches the sharpness assessPhoto reports', () {
    final bytes = _png(_checkerboard());

    expect(sharpnessScore(bytes), assessPhoto(bytes).sharpness);
  });
}

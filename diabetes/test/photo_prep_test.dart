import 'dart:typed_data';

import 'package:diabetes/fridge/scan/photo_prep.dart';
import 'package:diabetes/fridge/scan/scan_models.dart';
import 'package:diabetes/main.dart' show FoodType;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _jpeg(int width, int height, {int? orientation}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 80, 40));
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  group('preparePhoto', () {
    test('bakes the EXIF orientation into the kept pixels', () {
      // Orientation 6 = rotate 90° clockwise to display: 40x20 becomes 20x40.
      final photo = preparePhoto(_jpeg(40, 20, orientation: 6));

      expect(photo.original.width, 20);
      expect(photo.original.height, 40);
      expect(photo.originalWidth, 20);
      expect(photo.originalHeight, 40);
    });

    test('shrinks a large photo to a 2048 px overview and keeps the original',
        () {
      final photo = preparePhoto(_jpeg(3000, 1500));

      expect(photo.original.width, 3000);
      expect(photo.overviewWidth, 2048);
      expect(photo.overviewHeight, 1024);
      expect(photo.overviewScale, closeTo(2048 / 3000, 1e-9));
      final decoded = img.decodeJpg(photo.overviewJpeg)!;
      expect(decoded.width, 2048);
      expect(decoded.height, 1024);
    });

    test('never upscales a small photo', () {
      final photo = preparePhoto(_jpeg(300, 200));

      expect(photo.overviewWidth, 300);
      expect(photo.overviewHeight, 200);
      expect(photo.overviewScale, 1);
      expect(img.decodeJpg(photo.overviewJpeg)!.width, 300);
    });

    test('overview is a decodable JPEG', () {
      final photo = preparePhoto(_jpeg(64, 48));

      // JPEG magic bytes, then a full decode.
      expect(photo.overviewJpeg.sublist(0, 2), [0xFF, 0xD8]);
      expect(img.decodeJpg(photo.overviewJpeg), isNotNull);
    });

    test('maxKeptSide caps the kept pixels but reports the real size', () {
      final photo = preparePhoto(_jpeg(400, 200), maxKeptSide: 100);

      expect(photo.original.width, 100);
      expect(photo.original.height, 50);
      expect(photo.originalWidth, 400);
      expect(photo.originalHeight, 200);
    });

    test('rejects bytes that are not an image', () {
      expect(
        () => preparePhoto(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  group('preparePhotoAsync (engine codec)', () {
    testWidgets('decodes to the right sizes with an overview <= 2048',
        (tester) async {
      await tester.runAsync(() async {
        final photo = await preparePhotoAsync(_jpeg(2600, 1300));

        expect(photo.original.width, 2600);
        expect(photo.original.height, 1300);
        expect(photo.originalWidth, 2600);
        expect(photo.originalHeight, 1300);
        expect(photo.overviewWidth, closeTo(2048, 1));
        expect(photo.overviewHeight, closeTo(1024, 1));
        expect(photo.overviewJpeg.sublist(0, 2), [0xFF, 0xD8]);
        final decoded = img.decodeJpg(photo.overviewJpeg)!;
        expect(decoded.width, photo.overviewWidth);
        expect(decoded.height, photo.overviewHeight);
      });
    });

    testWidgets('maxKeptSide caps the kept pixels, not the reported size',
        (tester) async {
      await tester.runAsync(() async {
        final photo = await preparePhotoAsync(
          _jpeg(400, 200),
          maxKeptSide: 100,
        );

        expect(photo.original.width, closeTo(100, 1));
        expect(photo.original.height, closeTo(50, 1));
        expect(photo.originalWidth, 400);
        expect(photo.originalHeight, 200);
        expect(photo.overviewWidth, photo.original.width);
      });
    });

    testWidgets('never upscales a small photo', (tester) async {
      await tester.runAsync(() async {
        final photo = await preparePhotoAsync(_jpeg(300, 200));

        expect(photo.original.width, 300);
        expect(photo.overviewWidth, 300);
        expect(photo.overviewHeight, 200);
        expect(photo.overviewScale, 1);
      });
    });

    testWidgets('delivers an upright photo whatever the EXIF orientation',
        (tester) async {
      await tester.runAsync(() async {
        final photo = await preparePhotoAsync(_jpeg(40, 20, orientation: 6));

        expect(photo.original.width, 20);
        expect(photo.original.height, 40);
        expect(photo.originalWidth, 20);
        expect(photo.originalHeight, 40);
        expect(photo.overviewWidth, 20);
        expect(photo.overviewHeight, 40);
      });
    });

    testWidgets('rejects bytes that are not an image', (tester) async {
      await tester.runAsync(() async {
        await expectLater(
          preparePhotoAsync(Uint8List.fromList([1, 2, 3])),
          throwsFormatException,
        );
      });
    });
  });

  group('rotateForTilt', () {
    test('90 degrees swaps the sides; a small angle grows the canvas', () {
      final image = img.Image(width: 100, height: 50);

      final quarter = rotateForTilt(image, 90);
      expect([quarter.width, quarter.height], [50, 100]);

      final small = rotateForTilt(image, 15);
      expect(small.width, greaterThan(100));
      expect(small.height, greaterThan(50));
    });
  });

  group('rotateBox', () {
    test('90 degrees clockwise moves the top-left quadrant to the top-right',
        () {
      // 200x100 image, box over its top-left quadrant.
      final box = rotateBox([0, 0, 500, 500], 90, 200, 100);

      expect(box, [0, 500, 500, 1000]);
    });

    test('the whole image maps to the whole rotated canvas', () {
      expect(rotateBox([0, 0, 1000, 1000], 15, 400, 300), [0, 0, 1000, 1000]);
    });

    test('a centred box stays centred and grows a little at a small angle', () {
      final box = rotateBox([400, 400, 600, 600], 12, 400, 400);

      expect(box[0] + box[2], closeTo(1000, 1));
      expect(box[1] + box[3], closeTo(1000, 1));
      expect(box[3] - box[1], greaterThan(150));
    });
  });

  group('straightenIfTilted', () {
    const item = ScannedItem(
      name: 'Milk',
      foodType: FoodType.dairy,
      box2d: [0, 0, 500, 500],
    );

    test('is skipped at 10 degrees or less', () {
      final photo = preparePhoto(_jpeg(80, 40));

      for (final tilt in [0.0, 4.0, -10.0, 10.0]) {
        final result = straightenIfTilted(photo, tilt, items: [item]);
        expect(result.rotated, isFalse);
        expect(identical(result.photo, photo), isTrue);
        expect(result.items.single.box2d, [0, 0, 500, 500]);
      }
    });

    test('rotates the kept original and the boxes above 10 degrees', () {
      final photo = preparePhoto(_jpeg(80, 40));

      final result = straightenIfTilted(photo, 90, items: [item]);

      expect(result.rotated, isTrue);
      expect(result.photo.original.width, 40);
      expect(result.photo.original.height, 80);
      expect(result.photo.overviewWidth, 40);
      expect(result.items.single.box2d, [0, 500, 500, 1000]);
    });
  });
}

import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart' show XFile;
import 'package:diabetes/fridge/burst_capture.dart';
import 'package:diabetes/fridge/photo_quality.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

final _png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));

const _fine = PhotoQuality(sharpness: 600, clippedFraction: 0.001);
const _blurry = PhotoQuality(sharpness: 100, clippedFraction: 0.001);
const _bright = PhotoQuality(sharpness: 600, clippedFraction: 0.2);

List<Uint8List>? _result;

/// Opens the sheet from a button, as the fridge page does, so a pop is seen.
Future<void> _open(
  WidgetTester tester, {
  Future<Future<XFile> Function()> Function()? openCamera,
  Future<Uint8List?> Function()? pickPhoto,
  Future<BurstResult> Function(Future<XFile> Function())? burst,
  Future<PhotoQuality> Function(Uint8List)? assess,
}) async {
  _result = null;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              _result = await showModalBottomSheet<List<Uint8List>>(
                context: context,
                isScrollControlled: true,
                builder: (_) => FridgeCameraSheet(
                  openCamera: openCamera,
                  pickPhoto: pickPhoto,
                  burst: burst,
                  assess: assess,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<Future<XFile> Function()> _fakeCamera() async =>
    () async => XFile.fromData(_png);

Future<BurstResult> _instantBurst(Future<XFile> Function() take) async =>
    BurstResult(
      bytes: _png,
      scores: const [1, 2],
      elapsed: const Duration(milliseconds: 100),
    );

Future<void> _shoot(WidgetTester tester) async {
  await tester.tap(find.text('Take a picture'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Take picture'));
  await tester.pumpAndSettle();
}

Future<void> _upload(WidgetTester tester) async {
  await tester.tap(find.text('Upload a photo'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('camera sheet opens on a two-option chooser', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FridgeCameraSheet())),
    );
    await tester.pump();

    // The chooser offers both a live-capture and an upload path. It does not
    // touch the camera plugin until "Take a picture" is tapped, so simply
    // rendering it is safe in a widget test.
    expect(find.widgetWithText(FilledButton, 'Take a picture'), findsOneWidget);
    expect(find.text('Upload a photo'), findsOneWidget);
  });

  testWidgets('the shutter says "Hold still…" while the burst runs', (
    tester,
  ) async {
    final burst = Completer<BurstResult>();
    await _open(
      tester,
      openCamera: _fakeCamera,
      burst: (_) => burst.future,
      assess: (_) async => _fine,
    );
    await tester.tap(find.text('Take a picture'));
    await tester.pumpAndSettle();
    expect(find.text('Take picture'), findsOneWidget);

    await tester.tap(find.text('Take picture'));
    await tester.pump();
    expect(find.text('Hold still…'), findsOneWidget);
    final shutter = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Hold still…'),
    );
    expect(shutter.onPressed, isNull);

    burst.complete(
      BurstResult(bytes: _png, scores: const [1], elapsed: Duration.zero),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hold still…'), findsNothing);
    expect(find.text('Scan photo'), findsOneWidget);
  });

  testWidgets('a good photo goes straight to the strip and is returned', (
    tester,
  ) async {
    await _open(
      tester,
      openCamera: _fakeCamera,
      burst: _instantBurst,
      assess: (_) async => _fine,
    );
    await _shoot(tester);

    expect(find.text('Looks blurry, hold steady and retake'), findsNothing);
    expect(find.text('Scan photo'), findsOneWidget);
    expect(find.text('Add another photo'), findsOneWidget);

    await tester.tap(find.text('Scan photo'));
    await tester.pumpAndSettle();
    expect(_result, hasLength(1));
    expect(_result!.single, _png);
  });

  // Replaces the old 'a blurry photo warns, and Use anyway proceeds' test:
  // there is no blocking screen any more, the photo is simply added.
  testWidgets('a blurry photo is added at once with a note on its thumbnail', (
    tester,
  ) async {
    await _open(
      tester,
      openCamera: _fakeCamera,
      burst: _instantBurst,
      assess: (_) async => _blurry,
    );
    await _shoot(tester);

    expect(find.text('Check your photo'), findsNothing);
    expect(find.text('Retake'), findsNothing);
    expect(find.text('Use anyway'), findsNothing);
    expect(find.byKey(const Key('fridgePhotoThumb0')), findsOneWidget);
    expect(find.text('Looks blurry — retake if you can'), findsOneWidget);
    expect(find.bySemanticsLabel('Photo 1: Looks blurry — retake if you can'),
        findsOneWidget);

    await tester.tap(find.text('Scan photo'));
    await tester.pumpAndSettle();
    expect(_result, hasLength(1));
  });

  // Replaces 'an over-exposed photo gets the lighting message'.
  testWidgets('an over-exposed photo gets the lighting note', (tester) async {
    await _open(
      tester,
      pickPhoto: () async => _png,
      assess: (_) async => _bright,
    );
    await _upload(tester);

    expect(find.text('Bright light behind'), findsOneWidget);
    expect(find.text('Scan photo'), findsOneWidget);
  });

  // Replaces 'Retake goes back to the camera': the thumbnail's remove button
  // is the retake path now.
  testWidgets('removing a blurry photo returns to the chooser to retake', (
    tester,
  ) async {
    await _open(
      tester,
      openCamera: _fakeCamera,
      burst: _instantBurst,
      assess: (_) async => _blurry,
    );
    await _shoot(tester);

    await tester.tap(find.byKey(const Key('fridgePhotoRemove0')));
    await tester.pumpAndSettle();

    expect(find.text('Take a picture'), findsOneWidget);
    expect(find.text('Looks blurry — retake if you can'), findsNothing);
  });

  testWidgets('the note appears only after the background check finishes', (
    tester,
  ) async {
    final check = Completer<PhotoQuality>();
    await _open(
      tester,
      pickPhoto: () async => _png,
      assess: (_) => check.future,
    );
    await _upload(tester);

    // The photo and the Scan button are already there, check still running.
    expect(find.byKey(const Key('fridgePhotoThumb0')), findsOneWidget);
    expect(find.text('Scan photo'), findsOneWidget);
    expect(find.text('Looks blurry — retake if you can'), findsNothing);

    check.complete(_blurry);
    await tester.pumpAndSettle();
    expect(find.text('Looks blurry — retake if you can'), findsOneWidget);
  });

  testWidgets('a check that finishes after removal is ignored', (tester) async {
    final check = Completer<PhotoQuality>();
    await _open(
      tester,
      pickPhoto: () async => _png,
      assess: (_) => check.future,
    );
    await _upload(tester);
    await tester.tap(find.byKey(const Key('fridgePhotoRemove0')));
    await tester.pumpAndSettle();

    check.complete(_blurry);
    await tester.pumpAndSettle();
    expect(find.text('Looks blurry — retake if you can'), findsNothing);
  });

  testWidgets('an "Adding photo…" placeholder shows as the bytes arrive', (
    tester,
  ) async {
    final picked = Completer<Uint8List?>();
    await _open(
      tester,
      pickPhoto: () => picked.future,
      assess: (_) async => _fine,
    );
    await tester.tap(find.text('Upload a photo'));
    await tester.pump();

    picked.complete(_png);
    await tester.pump();
    expect(find.text('Adding photo…'), findsOneWidget);
    expect(find.byKey(const Key('fridgePhotoPending')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Adding photo…'), findsNothing);
    expect(find.byKey(const Key('fridgePhotoThumb0')), findsOneWidget);
  });

  testWidgets('Upload is disabled with a spinner while the picker is open', (
    tester,
  ) async {
    var opened = 0;
    final picked = Completer<Uint8List?>();
    await _open(
      tester,
      pickPhoto: () {
        opened++;
        return picked.future;
      },
      assess: (_) async => _fine,
    );
    await tester.tap(find.text('Upload a photo'));
    await tester.pump();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Upload a photo'),
    );
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Upload a photo'), warnIfMissed: false);
    await tester.pump();
    expect(opened, 1);

    // Cancelling the picker re-enables the button.
    picked.complete(null);
    await tester.pumpAndSettle();
    final again = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Upload a photo'),
    );
    expect(again.onPressed, isNotNull);
  });

  testWidgets('photos can be added up to three and removed', (tester) async {
    await _open(tester, pickPhoto: () async => _png, assess: (_) async => _fine);
    await _upload(tester);
    expect(find.text('Scan photo'), findsOneWidget);

    for (final expected in ['Scan 2 photos', 'Scan 3 photos']) {
      await tester.tap(find.text('Add another photo'));
      await tester.pumpAndSettle();
      expect(find.text('Take a picture'), findsOneWidget);
      await _upload(tester);
      expect(find.text(expected), findsOneWidget);
    }

    // Three is the most: no way to add a fourth.
    expect(find.text('Add another photo'), findsNothing);
    expect(find.byKey(const Key('fridgePhotoThumb2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('fridgePhotoRemove1')));
    await tester.pumpAndSettle();
    expect(find.text('Scan 2 photos'), findsOneWidget);
    expect(find.text('Add another photo'), findsOneWidget);

    await tester.tap(find.text('Scan 2 photos'));
    await tester.pumpAndSettle();
    expect(_result, hasLength(2));
  });

  testWidgets('removing the last photo returns to the chooser', (tester) async {
    await _open(tester, pickPhoto: () async => _png, assess: (_) async => _fine);
    await _upload(tester);

    await tester.tap(find.byKey(const Key('fridgePhotoRemove0')));
    await tester.pumpAndSettle();

    expect(find.text('Take a picture'), findsOneWidget);
    expect(find.text('Scan photo'), findsNothing);
  });

  testWidgets('the new buttons are at least 48 dp and labelled', (
    tester,
  ) async {
    await _open(tester, pickPhoto: () async => _png, assess: (_) async => _fine);
    await _upload(tester);

    for (final key in const [
      Key('fridgeScanPhotos'),
      Key('fridgeAddAnotherPhoto'),
      Key('fridgePhotoRemove0'),
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.height, greaterThanOrEqualTo(48), reason: '$key');
      expect(size.width, greaterThanOrEqualTo(48), reason: '$key');
    }
    expect(find.byTooltip('Remove photo 1'), findsOneWidget);
  });
}

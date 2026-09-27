import 'dart:async';
import 'dart:typed_data';

import 'package:diabetes/fridge/fridge_scan_dialog.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 1×1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  late Completer<List<FoodItem>> scan;
  FridgeScanResult? result;
  late bool closed;

  Future<void> open(WidgetTester tester) async {
    scan = Completer();
    result = null;
    closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<FridgeScanResult>(
                context: context,
                barrierDismissible: false,
                builder: (_) => FridgeScanDialog(
                  imageBytes: _png,
                  detect: (_) => scan.future,
                ),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('shows progress, then returns detected foods', (tester) async {
    await open(tester);
    expect(find.text('Finding foods…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    scan.complete(const [
      FoodItem(name: 'Eggs', amount: '12', foodType: FoodType.protein),
    ]);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result!.foods.single.name, 'Eggs');
  });

  testWidgets('cancel closes immediately and ignores the late result', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('fridgeScanCancel')));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);

    scan.complete(const []);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed scan returns the error', (tester) async {
    await open(tester);
    scan.completeError(Exception('boom'));
    await tester.pumpAndSettle();
    expect(result!.error, isNotNull);
  });
}

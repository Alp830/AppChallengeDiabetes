import 'dart:async';
import 'dart:typed_data';

import 'package:diabetes/ai/ai_retry.dart';
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
                  detect: (_, _) => scan.future,
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

  group('retries', () {
    late List<Completer<List<FoodItem>>> pending;
    late bool dialogClosed;
    FridgeScanResult? scanResult;

    Future<void> openRetrying(WidgetTester tester) async {
      pending = [];
      dialogClosed = false;
      scanResult = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                scanResult = await showDialog<FridgeScanResult>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => FridgeScanDialog(
                    imageBytes: _png,
                    // Zero spacing keeps the test instant; ai_retry_test
                    // already covers the real 2 s wait.
                    retryPolicy: const AiRetryPolicy(delay: Duration.zero),
                    detect: (_, _) {
                      final completer = Completer<List<FoodItem>>();
                      pending.add(completer);
                      return completer.future;
                    },
                  ),
                );
                dialogClosed = true;
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

    Future<void> failAttempt(WidgetTester tester) async {
      pending
          .removeAt(0)
          .completeError(AiRequestException.fromStatus(503, 'busy'));
      await tester.pump();
      await tester.pump(Duration.zero);
    }

    testWidgets('two hiccups then the foods, counting the tries', (
      tester,
    ) async {
      await openRetrying(tester);
      expect(find.byKey(const Key('aiRetryStatus')), findsNothing);

      await failAttempt(tester);
      expect(find.text('AI request failed. Retrying 2/5'), findsOneWidget);
      await failAttempt(tester);
      expect(find.text('AI request failed. Retrying 3/5'), findsOneWidget);

      pending.removeAt(0).complete(const [
        FoodItem(name: 'Eggs', amount: '12', foodType: FoodType.protein),
      ]);
      await tester.pumpAndSettle();

      expect(dialogClosed, isTrue);
      expect(scanResult!.foods.single.name, 'Eggs');
    });

    testWidgets('five failures keep the photo and offer Try again', (
      tester,
    ) async {
      await openRetrying(tester);
      for (var i = 0; i < 5; i++) {
        await failAttempt(tester);
      }
      await tester.pumpAndSettle();

      expect(dialogClosed, isFalse, reason: 'the error stays in the dialog');
      expect(find.text("Couldn't read the photo"), findsOneWidget);
      expect(find.byType(Image), findsOneWidget, reason: 'photo kept');
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Retrying'), findsNothing);
      expect(find.byKey(const Key('fridgeScanTryAgain')), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.byKey(const Key('fridgeScanTryAgain')));
      await tester.pump();
      expect(pending, hasLength(1), reason: 'a fresh run on the same bytes');
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('Retrying'), findsNothing);

      pending.removeAt(0).complete(const [
        FoodItem(name: 'Eggs', amount: '12', foodType: FoodType.protein),
      ]);
      await tester.pumpAndSettle();
      expect(scanResult!.foods.single.name, 'Eggs');
    });

    testWidgets('Close leaves without a result', (tester) async {
      await openRetrying(tester);
      for (var i = 0; i < 5; i++) {
        await failAttempt(tester);
      }
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(dialogClosed, isTrue);
      expect(scanResult, isNull);
    });

    testWidgets('cancelling mid-retry stops the attempts', (tester) async {
      await openRetrying(tester);
      await failAttempt(tester);
      expect(find.text('AI request failed. Retrying 2/5'), findsOneWidget);
      expect(pending, hasLength(1));

      await tester.tap(find.byKey(const Key('fridgeScanCancel')));
      await tester.pumpAndSettle();
      expect(scanResult, isNull);

      pending
          .removeAt(0)
          .completeError(AiRequestException.fromStatus(503, 'busy'));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      expect(pending, isEmpty, reason: 'no attempt after cancel');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a rejected photo fails after one call', (tester) async {
      await openRetrying(tester);
      pending
          .removeAt(0)
          .completeError(AiRequestException.fromStatus(400, 'bad image'));
      await tester.pumpAndSettle();

      expect(pending, isEmpty);
      expect(find.text("Couldn't read the photo"), findsOneWidget);
      expect(
        find.text("That request didn't work. Try changing it and try again."),
        findsOneWidget,
      );
    });
  });
}

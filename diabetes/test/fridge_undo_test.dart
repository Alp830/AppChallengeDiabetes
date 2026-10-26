import 'package:diabetes/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deleting many fridge items in a row must leave one Undo message, for the
/// latest removal, not a queue that plays out one message at a time.
void main() {
  late TestGesture mouse;

  String name(int i) => 'Item${i.toString().padLeft(2, '0')}';

  Future<void> pumpFridge(WidgetTester tester, int count) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FridgePage(
            initialItems: [
              for (var i = 0; i < count; i++)
                StoredFoodItem(
                  id: 'id$i',
                  foodItem: FoodItem(
                    name: name(i),
                    amount: '1',
                    foodType: FoodType.other,
                  ),
                ),
            ],
            onCommit: (_) async {},
          ),
        ),
      ),
    );
    mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
  }

  // The harness has no bottom bar, so the unsaved-changes bar covers the
  // floating snackbar; press its action directly.
  void pressUndo(WidgetTester tester) =>
      tester.widget<SnackBarAction>(find.byType(SnackBarAction).last).onPressed();

  Future<void> deleteTile(WidgetTester tester, int i) async {
    final x = find.byKey(Key('fridgeTileDelete_${name(i)}'));
    await mouse.moveTo(tester.getCenter(x));
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.down(tester.getCenter(x));
    await mouse.up();
    await tester.pump();
  }

  /// Tiles in reading order, as the names currently on screen.
  List<String> shownOrder(WidgetTester tester, int count) {
    final shown = [
      for (var i = 0; i < count; i++)
        if (find.text(name(i)).evaluate().isNotEmpty) name(i),
    ];
    shown.sort((a, b) {
      final pa = tester.getTopLeft(find.text(a));
      final pb = tester.getTopLeft(find.text(b));
      final byRow = pa.dy.compareTo(pb.dy);
      return byRow != 0 ? byRow : pa.dx.compareTo(pb.dx);
    });
    return shown;
  }

  testWidgets('33 removals leave one message, for the last item', (
    tester,
  ) async {
    await pumpFridge(tester, 33);
    for (var i = 0; i < 33; i++) {
      await deleteTile(tester, i);
    }
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining(name(32)), findsOneWidget);
    expect(find.textContaining('33 removed'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    // No queue of further messages once the last one has timed out.
    // The 4 s timer starts once the entrance animation ends, so step time.
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a single removal keeps the plain message', (tester) async {
    await pumpFridge(tester, 3);
    await deleteTile(tester, 1);
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.text('Removed ${name(1)}. Save to make it final.'),
      findsOneWidget,
    );
  });

  testWidgets('Undo restores only the last removal, in place, once', (
    tester,
  ) async {
    await pumpFridge(tester, 6);
    await deleteTile(tester, 2);
    await deleteTile(tester, 4);
    await tester.pump(const Duration(milliseconds: 50));
    expect(shownOrder(tester, 6), [name(0), name(1), name(3), name(5)]);

    pressUndo(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(shownOrder(tester, 6), [
      name(0),
      name(1),
      name(3),
      name(4),
      name(5),
    ]);
    expect(find.text(name(2)), findsNothing);

    // Second tap on the same (now stale) action does nothing.
    final undoButton = find.text('Undo');
    if (undoButton.evaluate().isNotEmpty) {
      pressUndo(tester);
      await tester.pump();
    }
    expect(shownOrder(tester, 6), [
      name(0),
      name(1),
      name(3),
      name(4),
      name(5),
    ]);
  });

  testWidgets('Undo after Discard does nothing', (tester) async {
    await pumpFridge(tester, 4);
    await deleteTile(tester, 1);
    await tester.pump(const Duration(milliseconds: 50));
    final undo = tester.widget<SnackBarAction>(find.byType(SnackBarAction));

    await tester.tap(find.byKey(const Key('fridgeDiscardBar')));
    await tester.pump();
    expect(shownOrder(tester, 4), [name(0), name(1), name(2), name(3)]);

    undo.onPressed();
    await tester.pump();
    expect(shownOrder(tester, 4), [name(0), name(1), name(2), name(3)]);
  });

  testWidgets('bulk delete shows one message and Undo restores the batch', (
    tester,
  ) async {
    await pumpFridge(tester, 5);
    await deleteTile(tester, 4);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text(name(1)));
    await tester.pump();
    await tester.tap(find.text(name(2)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    await tester.tap(find.byKey(const Key('deleteSelectedFridgeItems')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete 2 items'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Removed 2 items'), findsOneWidget);
    expect(shownOrder(tester, 5), [name(0), name(3)]);

    pressUndo(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(shownOrder(tester, 5), [name(0), name(1), name(2), name(3)]);
  });
}

import 'package:diabetes/fridge/selectable_fridge_grid.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long press enters touch selection mode and taps add items', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final items = [
      const FoodItem(name: 'Eggs', amount: '12', foodType: FoodType.protein),
      const FoodItem(
        name: 'Milk',
        amount: '1 carton',
        foodType: FoodType.dairy,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectableFridgeGrid(
            items: [
              for (var i = 0; i < items.length; i++) MapEntry(i, items[i]),
            ],
            onEdit: (_) {},
            onRemoveSelected: (_) async {},
            onBulkAction: (_, _) async {},
          ),
        ),
      ),
    );

    final touch = await tester.startGesture(
      tester.getCenter(find.text('Eggs')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await touch.moveTo(tester.getCenter(find.text('Milk')));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    await touch.up();
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Milk'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel selection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('normal mobile tap opens an item before selection mode', (
    tester,
  ) async {
    var edited = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectableFridgeGrid(
            items: const [
              MapEntry(
                0,
                FoodItem(
                  name: 'Eggs',
                  amount: '12',
                  foodType: FoodType.protein,
                ),
              ),
            ],
            onEdit: (_) => edited = true,
            onRemoveSelected: (_) async {},
            onBulkAction: (_, _) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Eggs'));
    expect(edited, isTrue);
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('touchscreen long press supports tapping and bulk delete', (
    tester,
  ) async {
    Set<int>? deleted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectableFridgeGrid(
            items: const [
              MapEntry(
                0,
                FoodItem(
                  name: 'Eggs',
                  amount: '12',
                  foodType: FoodType.protein,
                ),
              ),
              MapEntry(
                1,
                FoodItem(name: 'Milk', amount: '1', foodType: FoodType.dairy),
              ),
            ],
            onEdit: (_) {},
            onRemoveSelected: (items) async => deleted = items,
            onBulkAction: (_, _) async {},
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Eggs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Milk'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deleteSelectedFridgeItems')));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 items?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deleted, {0, 1});
  });
}

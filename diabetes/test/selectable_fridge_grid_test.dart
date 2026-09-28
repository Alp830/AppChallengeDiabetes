import 'package:diabetes/fridge/selectable_fridge_grid.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('items sit under their food type header in FoodType order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectableFridgeGrid(
            items: const [
              MapEntry(
                0,
                FoodItem(name: 'Rice', amount: '1', foodType: FoodType.grain),
              ),
              MapEntry(
                1,
                FoodItem(name: 'Milk', amount: '1', foodType: FoodType.dairy),
              ),
              MapEntry(
                2,
                FoodItem(name: 'Kale', amount: '1', foodType: FoodType.produce),
              ),
            ],
            onEdit: (_) {},
            onRemoveSelected: (_) async {},
            onBulkAction: (_, _) async {},
          ),
        ),
      ),
    );

    final produce = find.byKey(const Key('fridgeGroupHeader_produce'));
    final dairy = find.byKey(const Key('fridgeGroupHeader_dairy'));
    final grain = find.byKey(const Key('fridgeGroupHeader_grain'));
    expect(produce, findsOneWidget);
    expect(dairy, findsOneWidget);
    expect(grain, findsOneWidget);
    // Empty types get no header.
    expect(find.byKey(const Key('fridgeGroupHeader_protein')), findsNothing);
    expect(find.byKey(const Key('fridgeGroupHeader_snack')), findsNothing);
    expect(find.byKey(const Key('fridgeGroupHeader_drink')), findsNothing);
    expect(find.byKey(const Key('fridgeGroupHeader_other')), findsNothing);

    // Produce, then Dairy, then Grain: the declaration order of FoodType.
    expect(
      tester.getTopLeft(produce).dy,
      lessThan(tester.getTopLeft(dairy).dy),
    );
    expect(tester.getTopLeft(dairy).dy, lessThan(tester.getTopLeft(grain).dy));

    // Each item renders below its own header.
    expect(
      tester.getTopLeft(produce).dy,
      lessThan(tester.getTopLeft(find.text('Kale')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Kale')).dy,
      lessThan(tester.getTopLeft(dairy).dy),
    );

    // The total count stays on the top row.
    expect(find.text('3 items'), findsOneWidget);
  });

  testWidgets('expiry order is kept inside a group', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The host passes items already sorted by expiry; grouping must be stable.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectableFridgeGrid(
            items: [
              MapEntry(
                0,
                FoodItem(
                  name: 'Spinach',
                  amount: '1',
                  foodType: FoodType.produce,
                  expiryDate: DateTime(2026, 10, 1),
                ),
              ),
              MapEntry(
                1,
                FoodItem(
                  name: 'Milk',
                  amount: '1',
                  foodType: FoodType.dairy,
                  expiryDate: DateTime(2026, 10, 2),
                ),
              ),
              MapEntry(
                2,
                FoodItem(
                  name: 'Carrot',
                  amount: '1',
                  foodType: FoodType.produce,
                  expiryDate: DateTime(2026, 10, 5),
                ),
              ),
            ],
            onEdit: (_) {},
            onRemoveSelected: (_) async {},
            onBulkAction: (_, _) async {},
          ),
        ),
      ),
    );

    final spinach = tester.getTopLeft(find.text('Spinach'));
    final carrot = tester.getTopLeft(find.text('Carrot'));
    expect(
      spinach.dy < carrot.dy ||
          (spinach.dy == carrot.dy && spinach.dx < carrot.dx),
      isTrue,
      reason: 'Spinach expires first so it comes first inside Produce',
    );
  });

  testWidgets('a selection spanning two groups deletes both items', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Set<int>? deleted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectableFridgeGrid(
            items: const [
              MapEntry(
                0,
                FoodItem(name: 'Kale', amount: '1', foodType: FoodType.produce),
              ),
              MapEntry(
                1,
                FoodItem(name: 'Rice', amount: '1', foodType: FoodType.grain),
              ),
            ],
            onEdit: (_) {},
            onRemoveSelected: (items) async => deleted = items,
            onBulkAction: (_, _) async {},
          ),
        ),
      ),
    );

    final touch = await tester.startGesture(
      tester.getCenter(find.text('Kale')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await touch.moveTo(tester.getCenter(find.text('Rice')));
    await tester.pump();
    await touch.up();
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deleteSelectedFridgeItems')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete 2 items'));
    await tester.pumpAndSettle();
    expect(deleted, {0, 1});
  });

  testWidgets('group headers are announced with their type and count', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectableFridgeGrid(
            items: const [
              MapEntry(
                0,
                FoodItem(name: 'Rice', amount: '1', foodType: FoodType.grain),
              ),
              MapEntry(
                1,
                FoodItem(name: 'Oats', amount: '1', foodType: FoodType.grain),
              ),
              MapEntry(
                2,
                FoodItem(name: 'Kale', amount: '1', foodType: FoodType.produce),
              ),
            ],
            onEdit: (_) {},
            onRemoveSelected: (_) async {},
            onBulkAction: (_, _) async {},
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Grain, 2 items'), findsOneWidget);
    expect(find.bySemanticsLabel('Produce, 1 item'), findsOneWidget);
    handle.dispose();
  });

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
    await tester.tap(find.widgetWithText(FilledButton, 'Delete 2 items'));
    await tester.pumpAndSettle();
    expect(deleted, {0, 1});
  });
}

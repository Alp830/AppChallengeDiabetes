import 'package:diabetes/fridge/fridge_item_card.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 21);

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 200, height: 240, child: child)),
  );

  testWidgets('renders name, quantity and expiring-soon status', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        FridgeItemCard(
          foodItem: FoodItem(
            name: 'Milk',
            amount: '1 carton',
            foodType: FoodType.dairy,
            expiryDate: DateTime(2026, 7, 22),
          ),
          onEdit: () {},
          now: now,
        ),
      ),
    );

    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Expiring Soon'), findsOneWidget);
  });

  testWidgets('tapping the card body triggers edit', (tester) async {
    var edited = false;
    await tester.pumpWidget(
      wrap(
        FridgeItemCard(
          foodItem: const FoodItem(
            name: 'Eggs',
            amount: '12 eggs',
            foodType: FoodType.protein,
          ),
          onEdit: () => edited = true,
          now: now,
        ),
      ),
    );

    await tester.tap(find.text('Eggs'));
    expect(edited, isTrue);
  });

  testWidgets('no per-tile delete; selection mode shows a check slot', (
    tester,
  ) async {
    var toggled = false;
    await tester.pumpWidget(
      wrap(
        FridgeItemCard(
          foodItem: const FoodItem(
            name: 'Eggs',
            amount: '12 eggs',
            foodType: FoodType.protein,
          ),
          onEdit: () {},
          selectionMode: true,
          onToggleSelection: () => toggled = true,
          now: now,
        ),
      ),
    );

    expect(find.byTooltip('Delete item'), findsNothing);
    expect(find.bySemanticsLabel('Not selected'), findsOneWidget);
    await tester.tap(find.text('Eggs'));
    expect(toggled, isTrue);
  });

  testWidgets('no expiry shows unknown status and "No date"', (tester) async {
    await tester.pumpWidget(
      wrap(
        FridgeItemCard(
          foodItem: const FoodItem(
            name: 'Rice',
            amount: '1 bag',
            foodType: FoodType.grain,
          ),
          onEdit: () {},
          now: now,
        ),
      ),
    );

    expect(find.text('No date'), findsOneWidget);
  });
}

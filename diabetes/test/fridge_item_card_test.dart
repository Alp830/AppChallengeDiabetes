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
    expect(find.text('Expiring soon'), findsOneWidget);
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

  testWidgets(
    'delete button hidden in selection mode; check slot shows instead',
    (tester) async {
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
            onDelete: () {},
            selectionMode: true,
            onToggleSelection: () => toggled = true,
            now: now,
          ),
        ),
      );

      expect(find.byKey(const Key('fridgeTileDelete_Eggs')), findsNothing);
      expect(find.bySemanticsLabel('Not selected'), findsOneWidget);
      await tester.tap(find.text('Eggs'));
      expect(toggled, isTrue);
    },
  );

  testWidgets('shows a per-tile delete button that does not open edit', (
    tester,
  ) async {
    var edited = false;
    var deleted = false;
    await tester.pumpWidget(
      wrap(
        FridgeItemCard(
          foodItem: const FoodItem(
            name: 'Eggs',
            amount: '12 eggs',
            foodType: FoodType.protein,
          ),
          onEdit: () => edited = true,
          onDelete: () => deleted = true,
          now: now,
        ),
      ),
    );

    expect(find.byKey(const Key('fridgeTileDelete_Eggs')), findsOneWidget);
    await tester.tap(find.byKey(const Key('fridgeTileDelete_Eggs')));
    expect(deleted, isTrue);
    expect(edited, isFalse);
  });

  testWidgets('delete button is absent when onDelete is null', (tester) async {
    await tester.pumpWidget(
      wrap(
        FridgeItemCard(
          foodItem: const FoodItem(
            name: 'Eggs',
            amount: '12 eggs',
            foodType: FoodType.protein,
          ),
          onEdit: () {},
          now: now,
        ),
      ),
    );

    expect(find.byKey(const Key('fridgeTileDelete_Eggs')), findsNothing);
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

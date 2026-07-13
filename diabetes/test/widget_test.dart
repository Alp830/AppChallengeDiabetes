import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app supports an injected test home without Firebase', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MyApp(home: Scaffold(body: Text('Test home'))),
    );

    expect(find.text('Test home'), findsOneWidget);
  });

  testWidgets('fridge page can add, edit, and remove food items', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _FridgeHarness()));

    expect(find.text('No food added yet.'), findsOneWidget);

    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Food name'),
      'Eggs',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '12 eggs',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description (optional)'),
      'Breakfast food',
    );
    await tester.tap(find.text('Save Food'));
    await tester.pumpAndSettle();

    expect(find.text('Eggs'), findsOneWidget);
    expect(find.text('12 pieces'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit food'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Food name'),
      'Milk',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '1 carton',
    );
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('1 carton'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove food'));
    await tester.pumpAndSettle();
    expect(find.text('No food added yet.'), findsOneWidget);
  });

  testWidgets('agent page shows configurable meal recommendation controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AgentPage(foodItems: [])),
      ),
    );

    expect(
      find.widgetWithText(TextFormField, 'What do you want to eat?'),
      findsOneWidget,
    );
    expect(find.text('Recommend a Meal'), findsOneWidget);
    expect(find.text('Set a budget'), findsOneWidget);
  });
}

class _FridgeHarness extends StatefulWidget {
  const _FridgeHarness();

  @override
  State<_FridgeHarness> createState() => _FridgeHarnessState();
}

class _FridgeHarnessState extends State<_FridgeHarness> {
  final List<FoodItem> _items = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FridgePage(
        foodItems: _items,
        onAddFood: (foodItem) async {
          setState(() => _items.add(foodItem));
        },
        onAddFoods: (foodItems) async {
          setState(() => _items.addAll(foodItems));
        },
        onEditFood: (index, foodItem) async {
          setState(() => _items[index] = foodItem);
        },
        onRemoveFood: (index) async {
          setState(() => _items.removeAt(index));
        },
      ),
    );
  }
}

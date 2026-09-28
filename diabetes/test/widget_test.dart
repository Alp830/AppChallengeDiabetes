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

    expect(find.text('Your fridge is empty'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fridgeEmptyAdd')));
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
    await tester.tap(find.text('Save food'));
    await tester.pumpAndSettle();

    expect(find.text('Eggs'), findsOneWidget);

    // Editing is triggered by tapping the item card body.
    await tester.tap(find.text('Eggs'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Food name'),
      'Milk',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '1 carton',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Milk'), findsOneWidget);

    // Removal happens via the edit sheet's delete action.
    await tester.tap(find.text('Milk'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('fridgeEditDelete')));
    await tester.tap(find.byKey(const Key('fridgeEditDelete')));
    await tester.pumpAndSettle();
    expect(find.text('Your fridge is empty'), findsOneWidget);
  });

  testWidgets('agent page starts with a focused recommendation flow', (
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
    expect(find.text('Recommend a meal'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Set a budget'), findsNothing);
    expect(find.text('Cooking difficulty'), findsNothing);
    expect(find.text('Meal Lab'), findsNothing);
    expect(find.text('Log this meal'), findsNothing);
  });

  testWidgets('agent preferences reveal and retain secondary settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AgentPage(foodItems: [])),
      ),
    );

    await tester.tap(find.text('Preferences'));
    await tester.pumpAndSettle();
    expect(find.text('Set a budget'), findsOneWidget);
    expect(find.text("I'm in a hurry"), findsOneWidget);
    expect(find.text('Cooking difficulty'), findsOneWidget);

    await tester.tap(find.text('Set a budget'));
    await tester.pump();
    expect(find.byKey(const Key('agentBudgetField')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('agentBudgetField')), '15');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Done'));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('agentPreferencesButton')));
    await tester.pumpAndSettle();
    expect(find.text('15'), findsOneWidget);
  });

  testWidgets('agent meal type chips change the meal type', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AgentPage(foodItems: [])),
      ),
    );
    await tester.tap(find.byKey(const Key('agentMealType_snack')));
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('agentMealType_snack')))
          .selected,
      isTrue,
    );
  });

  testWidgets('example prompts fill the prompt field', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AgentPage(foodItems: [])),
      ),
    );
    await tester.tap(find.widgetWithText(ActionChip, 'Quick breakfast'));
    await tester.pump();
    final field = tester.widget<TextFormField>(
      find.byKey(const Key('agentFoodPrompt')),
    );
    expect(field.controller!.text, 'Quick breakfast');
  });

  testWidgets('failed recommendation shows a plain message and retry', (
    tester,
  ) async {
    // No API key in tests, so GeminiMealService.generate throws immediately —
    // and a missing key is not retryable, so it fails on the first attempt
    // with the setup message rather than the connection one.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AgentPage(foodItems: [])),
      ),
    );
    await tester.tap(find.byKey(const Key('recommendMealButton')));
    await tester.pumpAndSettle();
    expect(
      find.text("Meal ideas aren't set up on this device yet."),
      findsOneWidget,
    );
    expect(find.textContaining('API key'), findsNothing);
    expect(find.textContaining('Retrying'), findsNothing);
    expect(find.byKey(const Key('loadErrorRetry')), findsOneWidget);
  });
}

class _FridgeHarness extends StatefulWidget {
  const _FridgeHarness();

  @override
  State<_FridgeHarness> createState() => _FridgeHarnessState();
}

class _FridgeHarnessState extends State<_FridgeHarness> {
  final List<StoredFoodItem> _items = const [];
  final List<FridgeChangeSet> committed = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FridgePage(
        initialItems: _items,
        onCommit: (changes) async {
          committed.add(changes);
        },
      ),
    );
  }
}

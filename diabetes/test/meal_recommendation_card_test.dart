import 'package:diabetes/design/app_theme.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _meal = MealRecommendation(
  dishName: 'Veggie omelette',
  imagePrompt: '',
  reason: 'Uses your eggs before they expire.',
  ingredients: ['2 eggs', '1 cup spinach'],
  instructions: ['Whisk the eggs.', 'Cook with spinach.'],
  estimatedCostPerServing: r'$2-3/serving',
  usedFridgeItems: ['Eggs'],
  imageUrl: 'https://example.com/omelette.png',
);

Future<void> pumpCard(
  WidgetTester tester, {
  bool withAsk = true,
  bool isSaved = false,
  VoidCallback? onToggleSaved,
  bool showBalancingTweak = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ListView(
          children: [
            MealRecommendationCard(
              recommendation: _meal,
              diabetesEnabled: false,
              timeLabel: '≤ 20 min',
              difficultyLabel: 'Beginner',
              onLogMeal: () {},
              onMakeBalanced: () {},
              isSaved: isSaved,
              onToggleSaved: onToggleSaved,
              showBalancingTweak: showBalancingTweak,
              onAsk: withAsk ? (scope, {String? initialQuestion}) {} : null,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('decision facts sit directly under the dish name', (
    tester,
  ) async {
    await pumpCard(tester);
    final nameY = tester.getTopLeft(find.text('Veggie omelette')).dy;
    final reasonY = tester.getTopLeft(find.text(_meal.reason)).dy;
    for (final fact in ['≤ 20 min', r'$2-3/serving', 'Beginner']) {
      final y = tester.getTopLeft(find.text(fact)).dy;
      expect(y, greaterThan(nameY));
      expect(y, lessThan(reasonY));
    }
  });

  testWidgets('generated photo is labeled', (tester) async {
    await pumpCard(tester);
    expect(find.text('AI-generated image'), findsOneWidget);
  });

  testWidgets('ask affordance is visible when asking is possible', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.text('Tap a line to ask'), findsNWidgets(2));
  });

  testWidgets('one filled action; balancing is tonal', (tester) async {
    await pumpCard(tester);
    expect(find.widgetWithText(FilledButton, 'Log this meal'), findsOneWidget);
    expect(find.text('Add a balancing tweak'), findsOneWidget);
    expect(find.text('Make it more balanced?'), findsNothing);
  });

  testWidgets('save control is hidden until a save handler is given', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.byKey(const Key('recipeSaveButton')), findsNothing);
    expect(find.byKey(const Key('recipeUnsaveButton')), findsNothing);
  });

  testWidgets('unsaved card offers Save recipe and stays one filled action', (
    tester,
  ) async {
    var taps = 0;
    await pumpCard(tester, onToggleSaved: () => taps++);

    final save = find.byKey(const Key('recipeSaveButton'));
    expect(save, findsOneWidget);
    expect(find.text('Save recipe'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log this meal'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Save recipe'), findsOneWidget);

    // The actions sit below the fold on a card this long, so scroll first.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();
    await tester.tap(save);
    expect(taps, 1);
  });

  testWidgets('saved card reads Saved and announces how to remove it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpCard(tester, isSaved: true, onToggleSaved: () {});

    expect(find.byKey(const Key('recipeUnsaveButton')), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Save recipe'), findsNothing);
    expect(
      find.bySemanticsLabel('Saved. Tap to remove from saved recipes'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('a saved recipe view can hide the balancing tweak', (
    tester,
  ) async {
    await pumpCard(
      tester,
      isSaved: true,
      onToggleSaved: () {},
      showBalancingTweak: false,
    );

    expect(find.text('Add a balancing tweak'), findsNothing);
    expect(find.byKey(const Key('recipeUnsaveButton')), findsOneWidget);
  });

  group('budget and nutrition tradeoffs', () {
    MealRecommendation tradeoffMeal({
      String? mode,
      List<String> unmet = const [],
      String? notice,
      double? bound,
      double? budget,
    }) => MealRecommendation(
      dishName: 'Lentil stew',
      imagePrompt: '',
      reason: 'Hearty and cheap.',
      ingredients: const ['1 cup lentils'],
      instructions: const ['Simmer.'],
      estimatedCostPerServing: r'$2-3/serving',
      priorityMode: mode,
      unmetNutritionPreferences: unmet,
      constraintNotice: notice,
      estimatedCostUpperBoundPerServing: bound,
      requestBudgetPerServing: budget,
    );

    Future<void> pumpTradeoff(
      WidgetTester tester,
      MealRecommendation meal, {
      bool diabetes = false,
      double textScale = 1,
      bool fromOriginalRequest = false,
      bool showUnmetHeading = true,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: ListView(
                children: [
                  MealRecommendationCard(
                    recommendation: meal,
                    diabetesEnabled: diabetes,
                    budgetFromOriginalRequest: fromOriginalRequest,
                    showUnmetHeading: showUnmetHeading,
                    onAsk: (scope, {String? initialQuestion}) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    const heading = "I couldn't meet all your preferences within your budget";

    testWidgets('happy path shows only the estimates note', (tester) async {
      await pumpTradeoff(
        tester,
        tradeoffMeal(mode: 'allPreferences', bound: 3, budget: 5),
      );
      expect(find.byKey(const Key('mealPriorityModeLabel')), findsNothing);
      expect(find.byKey(const Key('mealConstraintNotice')), findsNothing);
      expect(find.byKey(const Key('mealOverBudgetLabel')), findsNothing);
      expect(find.text(heading), findsNothing);
      expect(find.text('Costs are estimates.'), findsOneWidget);
    });

    testWidgets('no budget means no estimates note', (tester) async {
      await pumpTradeoff(tester, tradeoffMeal());
      expect(find.byKey(const Key('mealCostEstimatesNote')), findsNothing);
    });

    testWidgets('budget-first fallback shows everything', (tester) async {
      await pumpTradeoff(
        tester,
        tradeoffMeal(
          mode: 'budgetFirst',
          unmet: const ['protein', 'fiber'],
          notice: 'Kept the cost low, so protein and fiber are lighter.',
          bound: 6,
          budget: 5,
        ),
      );
      expect(find.text('Budget-first option'), findsOneWidget);
      expect(find.byIcon(Icons.savings_outlined), findsOneWidget);
      expect(find.text('Over your budget'), findsOneWidget);
      expect(find.byKey(const Key('mealOverBudgetLabel')), findsOneWidget);
      expect(find.text(heading), findsOneWidget);
      expect(find.text('Relaxed: High protein, High fiber'), findsOneWidget);
      expect(
        find.text('Kept the cost low, so protein and fiber are lighter.'),
        findsOneWidget,
      );
      expect(find.text('Costs are estimates.'), findsOneWidget);
    });

    testWidgets('nutrition-first fallback is labeled', (tester) async {
      await pumpTradeoff(
        tester,
        tradeoffMeal(mode: 'nutritionFirst', bound: 8, budget: 5),
      );
      expect(find.text('Nutrition-first option'), findsOneWidget);
      expect(find.text('Over your budget'), findsOneWidget);
      expect(find.text(heading), findsNothing);
    });

    testWidgets('within budget never says over budget', (tester) async {
      await pumpTradeoff(
        tester,
        tradeoffMeal(mode: 'nutritionFirst', bound: 5, budget: 5),
      );
      expect(find.byKey(const Key('mealOverBudgetLabel')), findsNothing);
    });

    testWidgets('heading can be hidden when results share the screen', (
      tester,
    ) async {
      await pumpTradeoff(
        tester,
        tradeoffMeal(mode: 'budgetFirst', unmet: const ['carbs'], budget: 5),
        showUnmetHeading: false,
      );
      expect(find.text(heading), findsNothing);
      expect(find.text('Budget-first option'), findsOneWidget);
    });

    testWidgets('still shows with diabetes disabled and exposes semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpTradeoff(
        tester,
        tradeoffMeal(
          mode: 'budgetFirst',
          unmet: const ['protein'],
          notice: 'A note.',
          bound: 9,
          budget: 5,
        ),
        diabetes: false,
      );
      expect(find.byKey(const Key('mealConstraintNotice')), findsOneWidget);
      expect(find.bySemanticsLabel('Budget-first option'), findsOneWidget);
      expect(find.bySemanticsLabel('Over your budget'), findsOneWidget);
      expect(find.bySemanticsLabel('Note: A note.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r"^I couldn't meet all your")),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets(
      'saved recipes phrase budget fit as from the original request',
      (tester) async {
        await pumpTradeoff(
          tester,
          tradeoffMeal(budget: 6),
          fromOriginalRequest: true,
        );
        expect(
          find.textContaining(
            r'Budget fit is from when this was suggested ($6 per serving)',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('fits at 200% text on a 390px wide screen', (tester) async {
      await pumpTradeoff(
        tester,
        tradeoffMeal(
          mode: 'budgetFirst',
          unmet: const ['protein', 'carbs', 'fiber'],
          notice:
              'I kept this under your budget, so it gives up some of the '
              'nutrition priorities you chose.',
          bound: 9,
          budget: 5,
        ),
        textScale: 2,
        fromOriginalRequest: true,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Over your budget'), findsOneWidget);
    });
  });
}

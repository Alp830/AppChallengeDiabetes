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

Future<void> pumpCard(WidgetTester tester, {bool withAsk = true}) async {
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
}

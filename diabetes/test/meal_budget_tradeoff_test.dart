import 'dart:convert';

import 'package:diabetes/ai/ai_retry.dart';
import 'package:diabetes/main.dart';
import 'package:diabetes/settings/models/meal_nutrition_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_preferences_store.dart';

const _protein = MealNutritionPreferences(highProtein: true);

Map<String, dynamic> _meal(
  String name, {
  String? mode,
  List<String>? unmet,
  String? notice,
  num? bound,
}) => {
  'dishName': name,
  'imagePrompt': '',
  'reason': 'Because.',
  'ingredients': ['1 thing'],
  'instructions': ['Cook it.'],
  'estimatedCostPerServing': r'$2-3/serving',
  'priorityMode': ?mode,
  'unmetNutritionPreferences': ?unmet,
  'constraintNotice': ?notice,
  'estimatedCostUpperBoundPerServing': ?bound,
};

http.Response _reply(Object payload) => http.Response(
  jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': jsonEncode(payload)},
          ],
        },
      },
    ],
  }),
  200,
);

AgentRequest _request({
  int count = 1,
  MealNutritionPreferences prefs = MealNutritionPreferences.none,
  double? budget,
  MealType mealType = MealType.lunch,
  bool diabetes = false,
  bool balance = false,
}) => AgentRequest(
  useFridgeItems: false,
  hasBudget: budget != null,
  budget: budget?.toString(),
  budgetPerServing: budget,
  nutritionPreferences: prefs,
  hasTimeShortage: false,
  timeAvailable: null,
  foodPreferences: 'A quick meal',
  mealType: mealType,
  cookingExperience: CookingExperience.beginner,
  recommendationCount: count,
  fridgeItems: const [],
  feedbackHistory: const [],
  diabetesEnabled: diabetes,
  useMealBalance: balance,
);

void main() {
  late http.Client originalClient;

  setUp(() {
    originalClient = GeminiMealService.httpClient;
    GeminiMealService.debugApiKey = 'test-token';
  });

  tearDown(() {
    GeminiMealService.httpClient = originalClient;
    GeminiMealService.debugApiKey = null;
  });

  Future<List<MealRecommendation>> generate(
    AgentRequest request,
    Object payload,
  ) {
    GeminiMealService.httpClient = MockClient((_) async => _reply(payload));
    return GeminiMealService.generate(request);
  }

  final rejected = throwsA(isA<FormatException>());

  group('prompt', () {
    test('omits every nutrition section when nothing is selected', () {
      final prompt = GeminiMealService.buildPromptForTesting(
        _request(budget: 6),
      );
      expect(prompt, isNot(contains('Nutrition priorities')));
      expect(prompt, isNot(contains('priorityMode')));
      expect(prompt, isNot(contains('budgetFirst')));
      expect(prompt, contains('estimatedCostUpperBoundPerServing'));
    });

    test('adds the section and hierarchy for selected priorities', () {
      final prompt = GeminiMealService.buildPromptForTesting(
        _request(
          prefs: const MealNutritionPreferences(
            highProtein: true,
            highCarbs: true,
            highFiber: true,
          ),
          budget: 7.5,
        ),
      );
      expect(prompt, contains('Nutrition priorities'));
      expect(prompt, contains('High protein, High carbs, High fiber'));
      expect(prompt, contains('All selected priorities are equal'));
      expect(prompt, contains('not added sugar'));
      expect(prompt, contains('Do not promise gram amounts'));
      final first = prompt.indexOf("1. The user's explicitly requested");
      final second = prompt.indexOf('2. The budget and the fallback groups');
      final third = prompt.indexOf('3. The selected nutrition priorities');
      final fourth = prompt.indexOf('4. Soft guidance');
      expect(first, greaterThan(-1));
      expect(second, greaterThan(first));
      expect(third, greaterThan(second));
      expect(fourth, greaterThan(third));
      expect(prompt, contains('"priorityMode"'));
      expect(prompt, contains('"unmetNutritionPreferences"'));
      expect(prompt, contains('"constraintNotice"'));
      expect(prompt, contains('(only values from: protein, carbs, fiber)'));
      expect(prompt, contains("I couldn't find a meal meeting all your"));
      expect(prompt, contains('Never claim that no such meal exists'));
    });

    test('states the exact fallback split for 1 to 5 meals', () {
      const expected = {1: (1, 0), 2: (1, 1), 3: (2, 1), 4: (2, 2), 5: (3, 2)};
      expected.forEach((count, split) {
        final prompt = GeminiMealService.buildPromptForTesting(
          _request(count: count, prefs: _protein, budget: 5),
        );
        expect(
          prompt,
          contains(
            'exactly ${split.$1} "budgetFirst" and ${split.$2} '
            '"nutritionFirst"',
          ),
          reason: 'count $count',
        );
        expect(
          prompt,
          contains('If every one of the $count meals can satisfy all'),
        );
      });
    });

    test('without a budget there is no fallback split or bound field', () {
      final prompt = GeminiMealService.buildPromptForTesting(
        _request(count: 4, prefs: _protein),
      );
      expect(prompt, contains('Nutrition priorities'));
      expect(prompt, contains('no fallback split'));
      expect(prompt, isNot(contains('The per-serving budget is')));
      expect(prompt, isNot(contains('estimatedCostUpperBoundPerServing')));
      expect(prompt, isNot(contains('2. The budget and the fallback groups')));
      expect(prompt, contains('2. The selected nutrition priorities'));
    });

    test('evening and balance guidance defer to active priorities', () {
      final active = GeminiMealService.buildPromptForTesting(
        _request(
          count: 2,
          prefs: const MealNutritionPreferences(highCarbs: true),
          budget: 5,
          mealType: MealType.dinner,
          diabetes: true,
          balance: true,
        ),
      );
      expect(active, contains('These anchors are soft'));
      expect(
        active,
        contains('never overrides the selected nutrition priorities'),
      );
      expect(active, contains('when High carbs is selected'));
      expect(active, contains('follows the fallback groups'));
      expect(active, contains('never vetoes a selected nutrition priority'));
      expect(active, isNot(contains('Order the recommendations so the most')));

      final inactive = GeminiMealService.buildPromptForTesting(
        _request(mealType: MealType.dinner, diabetes: true, balance: true),
      );
      expect(
        inactive,
        contains(
          'Order the recommendations so the most sleep-compatible option '
          'comes first.',
        ),
      );
      expect(inactive, isNot(contains('These anchors are soft')));
    });
  });

  group('service validation', () {
    test('accepts a feasible all-preferences response', () async {
      final meals =
          await generate(_request(count: 2, prefs: _protein, budget: 6), [
            _meal('A', mode: 'allPreferences', unmet: [], bound: 4),
            _meal('B', mode: 'allPreferences', bound: 6),
          ]);
      expect(meals.map((m) => m.dishName), ['A', 'B']);
      expect(meals.first.priorityMode, 'allPreferences');
      expect(meals.last.estimatedCostUpperBoundPerServing, 6);
      expect(meals.every((m) => m.requestBudgetPerServing == 6), isTrue);
    });

    test('records no request budget when the request had none', () async {
      final meals = await generate(_request(), [_meal('A')]);
      expect(meals.single.requestBudgetPerServing, isNull);
    });

    test('accepts a 2/2 fallback and puts budget-first meals first', () async {
      final meals = await generate(
        _request(count: 4, prefs: _protein, budget: 5),
        [
          _meal(
            'N1',
            mode: 'nutritionFirst',
            notice: r'About $3 over.',
            bound: 8,
          ),
          _meal(
            'B1',
            mode: 'budgetFirst',
            unmet: ['protein'],
            notice:
                "I couldn't find a meal meeting all your preferences "
                'within your budget.',
            bound: 4,
          ),
          _meal(
            'N2',
            mode: 'nutritionFirst',
            notice: r'About $2 over.',
            bound: 7,
          ),
          _meal(
            'B2',
            mode: 'budgetFirst',
            unmet: ['protein'],
            notice: 'Relaxed protein.',
            bound: 5,
          ),
        ],
      );
      expect(meals.map((m) => m.dishName), ['B1', 'B2', 'N1', 'N2']);
    });

    test('a lone object answers a one-dish request only', () async {
      final one = await generate(_request(), _meal('Solo'));
      expect(one.single.dishName, 'Solo');
      await expectLater(generate(_request(count: 2), _meal('Solo')), rejected);
    });

    test('rejects a wrong count instead of trimming', () async {
      await expectLater(
        generate(_request(count: 1), [_meal('A'), _meal('B')]),
        rejected,
      );
      await expectLater(generate(_request(count: 2), [_meal('A')]), rejected);
      await expectLater(generate(_request(count: 1), <Object>[]), rejected);
    });

    test('rejects an over-budget single meal', () async {
      await expectLater(
        generate(_request(prefs: _protein, budget: 5), [
          _meal('A', mode: 'allPreferences', bound: 5.5),
        ]),
        rejected,
      );
    });

    test('rejects a fallback meal that has no notice', () async {
      await expectLater(
        generate(_request(count: 2, prefs: _protein, budget: 5), [
          _meal('B', mode: 'budgetFirst', unmet: ['protein'], bound: 4),
          _meal('N', mode: 'nutritionFirst', notice: 'Over.', bound: 8),
        ]),
        rejected,
      );
    });

    test('rejects an unselected unmet key and a missing bound', () async {
      await expectLater(
        generate(_request(prefs: _protein, budget: 5), [
          _meal(
            'A',
            mode: 'budgetFirst',
            unmet: ['fiber'],
            notice: 'n',
            bound: 4,
          ),
        ]),
        rejected,
      );
      await expectLater(
        generate(_request(prefs: _protein, budget: 5), [
          _meal('A', mode: 'allPreferences'),
        ]),
        rejected,
      );
    });

    test('plain requests need no nutrition metadata', () async {
      final meals = await generate(_request(count: 2), [
        _meal('A'),
        _meal('B'),
      ]);
      expect(meals, hasLength(2));
    });
  });

  group('MealRecommendation compatibility', () {
    test('an old saved recipe parses and serializes without new fields', () {
      final old = {
        'dishName': 'Old dish',
        'imagePrompt': 'a dish',
        'reason': 'Saved long ago.',
        'ingredients': ['rice'],
        'instructions': ['Boil.'],
        'usedFridgeItems': <String>[],
        'suggestedQuestions': <String>[],
      };
      final meal = MealRecommendation.fromJson(old);
      expect(meal.priorityMode, isNull);
      expect(meal.unmetNutritionPreferences, isEmpty);
      expect(meal.constraintNotice, isNull);
      expect(meal.estimatedCostUpperBoundPerServing, isNull);
      expect(meal.toJson(), old);
    });

    test('new fields round-trip through toJson and copyWith', () {
      final meal = MealRecommendation.fromJson(
        _meal(
          'New',
          mode: 'budgetFirst',
          unmet: ['protein'],
          notice: 'Relaxed.',
          bound: 3,
        ),
      ).copyWith(imageUrl: 'https://example.com/x.png');
      final json = meal.toJson();
      expect(json['priorityMode'], 'budgetFirst');
      expect(json['unmetNutritionPreferences'], ['protein']);
      expect(json['constraintNotice'], 'Relaxed.');
      expect(json['estimatedCostUpperBoundPerServing'], 3.0);
      final again = MealRecommendation.fromJson(json);
      expect(again.priorityMode, 'budgetFirst');
      expect(again.imageUrl, 'https://example.com/x.png');
    });
  });

  group('retry through the agent page', () {
    late AiRetryPolicy originalPolicy;
    late List<String> bodies;
    late List<http.Response> replies;

    setUp(() {
      originalPolicy = AgentPage.retryPolicy;
      AgentPage.retryPolicy = const AiRetryPolicy(delay: Duration.zero);
      bodies = [];
      replies = [];
      GeminiMealService.httpClient = MockClient((request) async {
        bodies.add(request.body);
        return replies.removeAt(0);
      });
    });

    tearDown(() => AgentPage.retryPolicy = originalPolicy);

    testWidgets('non-compliant output is retried, never shown', (tester) async {
      replies = [
        _reply([_meal('Missing metadata')]),
        _reply([_meal('Compliant dish', mode: 'allPreferences')]),
      ];
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentPage(
              foodItems: const [],
              userId: 'user-1',
              preferencesRepository: FakePreferencesStore(
                nutritionPreferences: _protein,
              ),
              diabetesEnabled: false,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('recommendMealButton')));
      await tester.pumpAndSettle();

      expect(bodies, hasLength(2));
      expect(bodies.toSet(), hasLength(1), reason: 'same request each try');
      expect(find.text('Missing metadata'), findsNothing);
      expect(find.text('Compliant dish'), findsOneWidget);
    });

    testWidgets('exhausted retries show the error and fabricate nothing', (
      tester,
    ) async {
      replies = [
        for (var i = 0; i < 5; i++) _reply([_meal('Bad'), _meal('Extra')]),
      ];
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AgentPage(foodItems: [])),
        ),
      );

      await tester.tap(find.byKey(const Key('recommendMealButton')));
      await tester.pumpAndSettle();

      expect(bodies, hasLength(5));
      expect(find.text('Bad'), findsNothing);
      expect(find.byKey(const Key('loadErrorRetry')), findsOneWidget);
    });
  });
}

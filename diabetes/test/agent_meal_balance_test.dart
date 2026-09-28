import 'dart:async';

import 'package:diabetes/ai/ai_retry.dart';
import 'package:diabetes/main.dart';
import 'package:diabetes/settings/data/app_preferences_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('balance targets are only added to the Agent prompt when selected', () {
    final disabled = GeminiMealService.buildPromptForTesting(_request(false));
    final enabled = GeminiMealService.buildPromptForTesting(_request(true));

    expect(disabled, isNot(contains('50% produce')));
    expect(disabled, isNot(contains('20-30 g protein')));
    expect(enabled, contains('20-30 g protein'));
    expect(enabled, contains('50% produce'));
    expect(enabled, contains('250-500 mL'));
    expect(enabled, contains("minority of the meal's calories"));
  });

  test('pantry staples guidance always appears in the prompt', () {
    final prompt = GeminiMealService.buildPromptForTesting(_request(false));
    expect(prompt, contains('Pantry staples:'));
    expect(prompt, contains('salt, pepper'));
  });

  test('substitution guidance only appears when using fridge items', () {
    final withoutFridge = GeminiMealService.buildPromptForTesting(
      _request(false),
    );
    final withFridge = GeminiMealService.buildPromptForTesting(
      _request(false, useFridgeItems: true),
    );

    expect(withoutFridge, isNot(contains('reasonable substitute')));
    expect(withFridge, contains('reasonable substitute'));
  });

  test('fridge items include expiry-derived freshness hints', () {
    final now = DateTime.now();
    final prompt = GeminiMealService.buildPromptForTesting(
      _request(
        false,
        useFridgeItems: true,
        fridgeItems: [
          FoodItem(
            name: 'Spinach',
            amount: '1 bag',
            foodType: FoodType.produce,
            expiryDate: now.add(const Duration(days: 1)),
          ),
          FoodItem(
            name: 'Yogurt',
            amount: '1 cup',
            foodType: FoodType.dairy,
            expiryDate: now.subtract(const Duration(days: 2)),
          ),
          const FoodItem(
            name: 'Rice',
            amount: '2 cups',
            foodType: FoodType.grain,
          ),
        ],
      ),
    );

    expect(prompt, contains('expires in 1 day(s) — use soon'));
    expect(prompt, contains('expired 2 day(s) ago'));
    expect(prompt, contains('no expiry date given'));
    expect(prompt, contains('use soon'));
  });

  test('cost anchor guidance appears in the budget section', () {
    final prompt = GeminiMealService.buildPromptForTesting(_request(false));
    expect(prompt, contains('estimatedCostPerServing'));
    expect(prompt, contains('tend to be cheap per serving'));
  });

  test('MealRecommendation.fromJson parses new transparency fields', () {
    final recommendation = MealRecommendation.fromJson({
      'dishName': 'Veggie stir fry',
      'imagePrompt': 'a plate of stir fry',
      'reason': 'Uses what you have',
      'ingredients': ['rice', 'spinach'],
      'instructions': ['Cook rice', 'Stir fry spinach'],
      'usedFridgeItems': ['Spinach', 'Rice'],
      'estimatedCostPerServing': r'$2-3/serving',
    });

    expect(recommendation.usedFridgeItems, ['Spinach', 'Rice']);
    expect(recommendation.estimatedCostPerServing, r'$2-3/serving');
  });

  test(
    'MealRecommendation.fromJson defaults new fields when omitted or malformed',
    () {
      final withoutFields = MealRecommendation.fromJson({
        'dishName': 'Veggie stir fry',
        'imagePrompt': 'a plate of stir fry',
        'reason': 'Uses what you have',
        'ingredients': ['rice'],
        'instructions': ['Cook rice'],
      });
      expect(withoutFields.usedFridgeItems, isEmpty);
      expect(withoutFields.estimatedCostPerServing, isNull);

      final mixedTypes = MealRecommendation.fromJson({
        'dishName': 'Veggie stir fry',
        'imagePrompt': 'a plate of stir fry',
        'reason': 'Uses what you have',
        'ingredients': ['rice'],
        'instructions': ['Cook rice'],
        'usedFridgeItems': ['Rice', 2, ''],
        'estimatedCostPerServing': '',
      });
      expect(mixedTypes.usedFridgeItems, ['Rice', '2']);
      expect(mixedTypes.estimatedCostPerServing, isNull);
    },
  );

  testWidgets('Agent loads and saves the remembered balance preference', (
    tester,
  ) async {
    final preferences = _FakePreferencesStore(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentPage(
            foodItems: const [],
            userId: 'user-1',
            preferencesRepository: preferences,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Preferences'));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<CheckboxListTile>(
      find.byKey(const Key('agentMealBalanceCheckbox')),
    );
    expect(checkbox.value, isTrue);

    await tester.tap(find.byKey(const Key('agentMealBalanceCheckbox')));
    await tester.pump();
    expect(preferences.saved, [false]);
  });

  group('GeminiMealService throws typed errors', () {
    late http.Client originalClient;

    setUp(() {
      originalClient = GeminiMealService.httpClient;
      GeminiMealService.debugApiKey = 'test-token';
    });

    tearDown(() {
      GeminiMealService.httpClient = originalClient;
      GeminiMealService.debugApiKey = null;
    });

    Future<void> expectGenerateError(
      http.Response response,
      Matcher matcher,
    ) async {
      GeminiMealService.httpClient = MockClient((_) async => response);
      await expectLater(
        GeminiMealService.generate(_request(false)),
        throwsA(matcher),
      );
    }

    test('a 503 is retryable, a 400 is not', () async {
      await expectGenerateError(
        http.Response('busy', 503),
        isA<AiRequestException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.retryable, 'retryable', isTrue),
      );
      await expectGenerateError(
        http.Response('bad', 400),
        isA<AiRequestException>().having(
          (e) => e.retryable,
          'retryable',
          isFalse,
        ),
      );
    });

    test('an empty or unparseable reply is a FormatException', () async {
      for (final body in const [
        '{"candidates": []}',
        '{"candidates": [{"content": {"parts": []}}]}',
        '{"candidates": [{"content": {"parts": [{"text": "{oops"}]}}]}',
        '{"candidates": [{"content": 7}]}',
      ]) {
        await expectGenerateError(
          http.Response(body, 200),
          isA<FormatException>(),
        );
      }
    });

    test('a safety block is not retryable', () async {
      await expectGenerateError(
        http.Response('{"promptFeedback": {"blockReason": "SAFETY"}}', 200),
        isA<AiRequestException>().having(
          (e) => e.retryable,
          'retryable',
          isFalse,
        ),
      );
    });

    test('a missing key fails with a non-retryable error', () async {
      GeminiMealService.debugApiKey = null;
      var called = false;
      GeminiMealService.httpClient = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      await expectLater(
        GeminiMealService.generate(_request(false)),
        throwsA(
          isA<AiRequestException>().having(
            (e) => e.retryable,
            'retryable',
            isFalse,
          ),
        ),
      );
      expect(called, isFalse);
    });
  });
}

AgentRequest _request(
  bool useMealBalance, {
  bool useFridgeItems = false,
  List<FoodItem> fridgeItems = const [],
}) => AgentRequest(
  useFridgeItems: useFridgeItems,
  hasBudget: false,
  budget: null,
  hasTimeShortage: false,
  timeAvailable: null,
  foodPreferences: 'A quick lunch',
  mealType: MealType.lunch,
  cookingExperience: CookingExperience.beginner,
  recommendationCount: 1,
  fridgeItems: fridgeItems,
  feedbackHistory: const [],
  useMealBalance: useMealBalance,
);

class _FakePreferencesStore implements AppPreferencesStore {
  _FakePreferencesStore(bool initial) : _controller = StreamController<bool>() {
    _controller.add(initial);
  }

  final StreamController<bool> _controller;
  final List<bool> saved = [];

  @override
  Future<void> saveMealBalanceAgentEnabled(String userId, bool enabled) async {
    saved.add(enabled);
    _controller.add(enabled);
  }

  @override
  Stream<bool> watchMealBalanceAgentEnabled(String userId) =>
      _controller.stream;

  @override
  Future<void> saveMealQaTipSeen(String userId) async => qaTipSaved = true;
  bool qaTipSaved = false;

  @override
  Stream<bool> watchMealQaTipSeen(String userId) => Stream<bool>.value(false);

  @override
  Future<void> completeFirstMealGuide(String userId) async =>
      firstMealGuideCompleted = true;
  bool firstMealGuideCompleted = false;

  @override
  Stream<bool> watchFirstMealGuidePending(String userId) =>
      Stream<bool>.value(false);
}

import 'dart:async';

import 'package:diabetes/main.dart';
import 'package:diabetes/settings/data/app_preferences_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('balance targets are only added to the Agent prompt when selected', () {
    final disabled = GeminiMealService.buildPromptForTesting(_request(false));
    final enabled = GeminiMealService.buildPromptForTesting(_request(true));

    expect(disabled, isNot(contains('50% produce')));
    expect(disabled, isNot(contains('20-30 g protein')));
    expect(enabled, contains('20-30 g protein'));
    expect(enabled, contains('50% produce'));
    expect(enabled, contains('250-500 mL'));
  });

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

    final checkbox = tester.widget<CheckboxListTile>(
      find.byKey(const Key('agentMealBalanceCheckbox')),
    );
    expect(checkbox.value, isTrue);

    await tester.tap(find.byKey(const Key('agentMealBalanceCheckbox')));
    await tester.pump();
    expect(preferences.saved, [false]);
  });
}

AgentRequest _request(bool useMealBalance) => AgentRequest(
  useFridgeItems: false,
  hasBudget: false,
  budget: null,
  hasTimeShortage: false,
  timeAvailable: null,
  foodPreferences: 'A quick lunch',
  mealType: MealType.lunch,
  cookingExperience: CookingExperience.beginner,
  recommendationCount: 1,
  fridgeItems: const [],
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
}

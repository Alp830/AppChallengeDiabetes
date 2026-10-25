import 'dart:async';
import 'dart:convert';

import 'package:diabetes/ai/ai_retry.dart';
import 'package:diabetes/main.dart';
import 'package:diabetes/settings/models/meal_nutrition_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_preferences_store.dart';

const _protein = Key('agentHighProteinCheckbox');
const _carbs = Key('agentHighCarbsCheckbox');
const _fiber = Key('agentHighFiberCheckbox');
const _loadError = "Couldn't load your saved nutrition priorities";
const _saveError = "Couldn't save your nutrition priorities. Try again.";

http.Response _recipeResponse() => http.Response(
  jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {
              'text': jsonEncode([
                {
                  'dishName': 'Lemon chicken bowl',
                  'imagePrompt': '',
                  'reason': 'Quick and filling.',
                  'ingredients': ['1 chicken breast'],
                  'instructions': ['Cook it.'],
                  'priorityMode': 'allPreferences',
                  'unmetNutritionPreferences': <String>[],
                  'constraintNotice': null,
                  'estimatedCostUpperBoundPerServing': 3,
                },
              ]),
            },
          ],
        },
      },
    ],
  }),
  200,
);

void main() {
  late http.Client originalClient;
  late AiRetryPolicy originalPolicy;
  late List<String> bodies;

  setUp(() {
    originalClient = GeminiMealService.httpClient;
    originalPolicy = AgentPage.retryPolicy;
    AgentPage.retryPolicy = const AiRetryPolicy(delay: Duration.zero);
    GeminiMealService.debugApiKey = 'test-token';
    bodies = [];
    GeminiMealService.httpClient = MockClient((request) async {
      bodies.add(request.body);
      return _recipeResponse();
    });
  });

  tearDown(() {
    GeminiMealService.httpClient = originalClient;
    GeminiMealService.debugApiKey = null;
    AgentPage.retryPolicy = originalPolicy;
  });

  Future<void> pumpAgent(
    WidgetTester tester, {
    FakePreferencesStore? store,
    String? userId = 'user-1',
  }) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentPage(
            foodItems: const [],
            userId: userId,
            preferencesRepository: store,
            diabetesEnabled: false,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openPreferences(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('agentPreferencesButton')));
    await tester.pumpAndSettle();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
  }

  bool? valueOf(WidgetTester tester, Key key) =>
      tester.widget<CheckboxListTile>(find.byKey(key)).value;

  bool enabled(WidgetTester tester, Key key) =>
      tester.widget<CheckboxListTile>(find.byKey(key)).onChanged != null;

  Future<void> tapBox(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pump();
    await tester.pump();
  }

  bool generateEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(const Key('recommendMealButton')))
          .onPressed !=
      null;

  group('nutrition priorities', () {
    testWidgets('three unchecked boxes with helper text by default', (
      tester,
    ) async {
      await pumpAgent(tester, store: FakePreferencesStore());
      await openPreferences(tester);

      expect(find.text('Nutrition priorities'), findsOneWidget);
      expect(find.text('High protein'), findsOneWidget);
      expect(find.text('High carbs'), findsOneWidget);
      expect(find.text('High fiber'), findsOneWidget);
      for (final key in [_protein, _carbs, _fiber]) {
        expect(valueOf(tester, key), isFalse);
        expect(enabled(tester, key), isTrue);
      }
    });

    testWidgets('boxes toggle independently and save each change', (
      tester,
    ) async {
      final store = FakePreferencesStore();
      await pumpAgent(tester, store: store);
      await openPreferences(tester);

      await tapBox(tester, _carbs);
      expect(valueOf(tester, _carbs), isTrue);
      expect(valueOf(tester, _protein), isFalse);
      expect(valueOf(tester, _fiber), isFalse);
      expect(
        store.savedNutritionPreferences.last,
        const MealNutritionPreferences(highCarbs: true),
      );

      await tapBox(tester, _fiber);
      expect(
        store.savedNutritionPreferences.last,
        const MealNutritionPreferences(highCarbs: true, highFiber: true),
      );
      expect(store.saveMealNutritionPreferencesCalls, 2);
    });

    testWidgets('all three can be on, then all off again', (tester) async {
      final store = FakePreferencesStore();
      await pumpAgent(tester, store: store);
      await openPreferences(tester);

      for (final key in [_protein, _carbs, _fiber]) {
        await tapBox(tester, key);
        expect(valueOf(tester, key), isTrue);
      }
      expect(
        store.savedNutritionPreferences.last,
        const MealNutritionPreferences(
          highProtein: true,
          highCarbs: true,
          highFiber: true,
        ),
      );
      for (final key in [_protein, _carbs, _fiber]) {
        await tapBox(tester, key);
        expect(valueOf(tester, key), isFalse);
      }
      expect(
        store.savedNutritionPreferences.last,
        MealNutritionPreferences.none,
      );
    });

    testWidgets('saved priorities come back after a remount', (tester) async {
      final store = FakePreferencesStore();
      await pumpAgent(tester, store: store);
      await openPreferences(tester);
      await tapBox(tester, _protein);
      await tapBox(tester, _fiber);
      await closeSheet(tester);

      await tester.pumpWidget(const SizedBox());
      await pumpAgent(tester, store: store);
      await openPreferences(tester);

      expect(valueOf(tester, _protein), isTrue);
      expect(valueOf(tester, _carbs), isFalse);
      expect(valueOf(tester, _fiber), isTrue);
    });

    testWidgets('values pushed from another device update the sheet', (
      tester,
    ) async {
      final store = FakePreferencesStore();
      await pumpAgent(tester, store: store);
      await openPreferences(tester);

      store.setMealNutritionPreferences(
        const MealNutritionPreferences(highCarbs: true),
      );
      await tester.pump();
      await tester.pump();

      expect(valueOf(tester, _carbs), isTrue);
    });

    testWidgets('subscribes once and cancels when the page goes away', (
      tester,
    ) async {
      final store = FakePreferencesStore();
      await pumpAgent(tester, store: store);
      await openPreferences(tester);
      await tapBox(tester, _protein);
      await closeSheet(tester);

      expect(store.watchMealNutritionPreferencesCalls, 1);
      expect(store.activeNutritionListeners, 1);

      await tester.pumpWidget(const SizedBox());
      expect(store.activeNutritionListeners, 0);
    });

    testWidgets('boxes and Generate wait for the first saved value', (
      tester,
    ) async {
      final store = FakePreferencesStore(
        nutritionPreferences: const MealNutritionPreferences(highFiber: true),
      )..watchMealNutritionPreferencesEmitsInitial = false;
      await pumpAgent(tester, store: store);

      expect(generateEnabled(tester), isFalse);
      await openPreferences(tester);
      for (final key in [_protein, _carbs, _fiber]) {
        expect(enabled(tester, key), isFalse);
      }

      store.setMealNutritionPreferences(
        const MealNutritionPreferences(highFiber: true),
      );
      await tester.pump();
      await tester.pump();

      expect(valueOf(tester, _fiber), isTrue);
      expect(enabled(tester, _protein), isTrue);
      await closeSheet(tester);
      expect(generateEnabled(tester), isTrue);
      expect(store.saveMealNutritionPreferencesCalls, 0);
    });

    testWidgets('a failed read is shown, never saves defaults, and retries', (
      tester,
    ) async {
      final store = FakePreferencesStore(
        nutritionPreferences: const MealNutritionPreferences(highProtein: true),
      )..watchMealNutritionPreferencesError = Exception('offline');
      await pumpAgent(tester, store: store);
      await openPreferences(tester);

      expect(find.text(_loadError), findsOneWidget);
      expect(
        find.byKey(const Key('agentNutritionRetryButton')),
        findsOneWidget,
      );
      expect(store.saveMealNutritionPreferencesCalls, 0);

      // Toggling after an error is local only: nothing is written.
      await tapBox(tester, _carbs);
      expect(valueOf(tester, _carbs), isTrue);
      expect(store.saveMealNutritionPreferencesCalls, 0);

      store.watchMealNutritionPreferencesError = null;
      await tester.tap(find.byKey(const Key('agentNutritionRetryButton')));
      await tester.pump();
      await tester.pump();

      expect(find.text(_loadError), findsNothing);
      expect(valueOf(tester, _protein), isTrue, reason: 'saved value wins');
      expect(valueOf(tester, _carbs), isFalse);
      expect(store.saveMealNutritionPreferencesCalls, 0);
      expect(store.watchMealNutritionPreferencesCalls, 2);
      expect(store.activeNutritionListeners, 1, reason: 'old one cancelled');
    });

    testWidgets('after a failed read Generate still works', (tester) async {
      final store = FakePreferencesStore()
        ..watchMealNutritionPreferencesError = Exception('offline');
      await pumpAgent(tester, store: store);

      expect(generateEnabled(tester), isTrue);
    });

    testWidgets('a failed save restores the last saved value and says so', (
      tester,
    ) async {
      final store = FakePreferencesStore(
        nutritionPreferences: const MealNutritionPreferences(highProtein: true),
      )..saveMealNutritionPreferencesError = Exception('offline');
      await pumpAgent(tester, store: store);
      await openPreferences(tester);

      await tapBox(tester, _carbs);

      expect(valueOf(tester, _carbs), isFalse);
      expect(valueOf(tester, _protein), isTrue);
      expect(find.text(_saveError), findsOneWidget);
      expect(enabled(tester, _carbs), isTrue, reason: 'can try again');

      store.saveMealNutritionPreferencesError = null;
      await tapBox(tester, _carbs);
      expect(valueOf(tester, _carbs), isTrue);
      expect(find.text(_saveError), findsNothing);
      expect(store.saveMealNutritionPreferencesCalls, 2);
    });

    testWidgets('only one write is in flight; boxes lock meanwhile', (
      tester,
    ) async {
      final gate = Completer<void>();
      final store = FakePreferencesStore()
        ..saveMealNutritionPreferencesGate = gate;
      await pumpAgent(tester, store: store);
      await openPreferences(tester);

      await tapBox(tester, _protein);
      for (final key in [_protein, _carbs, _fiber]) {
        expect(enabled(tester, key), isFalse);
      }
      await tapBox(tester, _carbs);
      await tapBox(tester, _fiber);
      expect(store.saveMealNutritionPreferencesCalls, 1);

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(enabled(tester, _carbs), isTrue);
      expect(valueOf(tester, _protein), isTrue);
      expect(valueOf(tester, _carbs), isFalse);
      expect(store.maxConcurrentNutritionSaves, 1);
    });

    testWidgets('keyboard focus returns to the toggled box after a save', (
      tester,
    ) async {
      final gate = Completer<void>();
      final store = FakePreferencesStore()
        ..saveMealNutritionPreferencesGate = gate;
      await pumpAgent(tester, store: store);
      await openPreferences(tester);

      final focusNode = tester
          .widget<CheckboxListTile>(find.byKey(_carbs))
          .focusNode!;
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(enabled(tester, _carbs), isFalse);

      gate.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(valueOf(tester, _carbs), isTrue);
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('dismissing the sheet mid-save is safe', (tester) async {
      final gate = Completer<void>();
      final store = FakePreferencesStore()
        ..saveMealNutritionPreferencesGate = gate;
      await pumpAgent(tester, store: store);
      await openPreferences(tester);

      await tapBox(tester, _protein);
      await closeSheet(tester);
      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      await openPreferences(tester);
      expect(valueOf(tester, _protein), isTrue);
    });

    testWidgets('a failed save after dismissal does not throw', (tester) async {
      final gate = Completer<void>();
      final store = FakePreferencesStore()
        ..saveMealNutritionPreferencesGate = gate
        ..saveMealNutritionPreferencesError = Exception('offline');
      await pumpAgent(tester, store: store);
      await openPreferences(tester);

      await tapBox(tester, _protein);
      await closeSheet(tester);
      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      await openPreferences(tester);
      expect(valueOf(tester, _protein), isFalse);
    });

    testWidgets('leaving the page mid-save is safe', (tester) async {
      final gate = Completer<void>();
      final store = FakePreferencesStore()
        ..saveMealNutritionPreferencesGate = gate;
      await pumpAgent(tester, store: store);
      await openPreferences(tester);
      await tapBox(tester, _protein);
      await closeSheet(tester);

      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('without a signed-in user changes stay local, nothing saved', (
      tester,
    ) async {
      final store = FakePreferencesStore();
      await pumpAgent(tester, store: store, userId: null);
      expect(generateEnabled(tester), isTrue);
      await openPreferences(tester);

      expect(enabled(tester, _protein), isTrue);
      await tapBox(tester, _protein);
      expect(valueOf(tester, _protein), isTrue);
      await closeSheet(tester);
      await openPreferences(tester);
      expect(valueOf(tester, _protein), isTrue);

      expect(store.saveMealNutritionPreferencesCalls, 0);
      expect(store.watchMealNutritionPreferencesCalls, 0);
    });

    testWidgets('does not touch the balance checkbox', (tester) async {
      final store = FakePreferencesStore();
      await pumpAgent(tester, store: store);
      await openPreferences(tester);

      await tapBox(tester, _protein);

      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('agentMealBalanceCheckbox')),
            )
            .value,
        isFalse,
      );
    });
  });

  group('request snapshot', () {
    testWidgets('the request carries the priorities and later edits do not '
        'regenerate or alter it', (tester) async {
      final store = FakePreferencesStore(
        nutritionPreferences: const MealNutritionPreferences(highProtein: true),
      );
      await pumpAgent(tester, store: store);

      await tester.tap(find.byKey(const Key('recommendMealButton')));
      await tester.pumpAndSettle();

      final state = tester.state<AgentPageState>(find.byType(AgentPage));
      expect(bodies, hasLength(1));
      expect(
        state.lastRequest!.nutritionPreferences,
        const MealNutritionPreferences(highProtein: true),
      );

      await openPreferences(tester);
      await tapBox(tester, _carbs);
      await closeSheet(tester);

      expect(bodies, hasLength(1), reason: 'changing a box never regenerates');
      expect(
        state.lastRequest!.nutritionPreferences,
        const MealNutritionPreferences(highProtein: true),
      );
    });

    test('copyWith keeps the exact nutrition snapshot', () {
      const prefs = MealNutritionPreferences(
        highProtein: true,
        highFiber: true,
      );
      final request = _request(nutritionPreferences: prefs);

      expect(
        request.copyWith(feedbackHistory: ['x']).nutritionPreferences,
        prefs,
      );
      expect(
        request.copyWith(recommendationCount: 1).nutritionPreferences,
        prefs,
      );
      expect(_request().nutritionPreferences, MealNutritionPreferences.none);
    });

    test('copyWith keeps the validated budget', () {
      final request = _request(budgetPerServing: 7.5);
      expect(request.copyWith(feedbackHistory: ['x']).budgetPerServing, 7.5);
    });
  });

  group('budget per serving', () {
    test('parseBudgetPerServing accepts positive decimals only', () {
      expect(parseBudgetPerServing('7.50'), 7.5);
      expect(parseBudgetPerServing(' 12 '), 12);
      expect(parseBudgetPerServing(r'$5'), 5);
      expect(parseBudgetPerServing('.5'), 0.5);
      for (final bad in [
        '',
        '   ',
        'abc',
        '0',
        '0.00',
        '-3',
        'NaN',
        'Infinity',
        '-Infinity',
        '1e400',
        '1,5',
        r'$',
        r'$$5',
        '5 dollars',
      ]) {
        expect(parseBudgetPerServing(bad), isNull, reason: 'input "$bad"');
      }
    });

    Future<void> enterBudget(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const Key('agentBudgetField')), text);
      await tester.pump();
    }

    Future<void> tapDone(WidgetTester tester) async {
      final done = find.widgetWithText(FilledButton, 'Done');
      await tester.ensureVisible(done);
      await tester.tap(done);
      await tester.pumpAndSettle();
    }

    testWidgets('label says per serving and bad values keep the sheet open', (
      tester,
    ) async {
      await pumpAgent(tester, store: FakePreferencesStore());
      await openPreferences(tester);
      await tester.tap(find.text('Set a budget'));
      await tester.pump();

      expect(find.text('Budget per serving'), findsOneWidget);

      for (final bad in ['', 'abc', '0', '-3', 'NaN', 'Infinity']) {
        await enterBudget(tester, bad);
        await tapDone(tester);
        expect(
          find.byKey(const Key('agentBudgetField')),
          findsOneWidget,
          reason: '"$bad" must not close the sheet',
        );
        expect(
          find.textContaining('Enter a budget'),
          findsOneWidget,
          reason: 'inline error for "$bad"',
        );
      }
    });

    testWidgets('7.50 and a leading dollar sign are accepted', (tester) async {
      await pumpAgent(tester, store: FakePreferencesStore());
      await openPreferences(tester);
      await tester.tap(find.text('Set a budget'));
      await tester.pump();

      await enterBudget(tester, '7.50');
      await tapDone(tester);
      expect(find.byKey(const Key('agentBudgetField')), findsNothing);

      await openPreferences(tester);
      await enterBudget(tester, r'$8');
      await tapDone(tester);
      expect(find.byKey(const Key('agentBudgetField')), findsNothing);
    });

    testWidgets('a valid budget reaches the request as a number', (
      tester,
    ) async {
      await pumpAgent(tester, store: FakePreferencesStore());
      await openPreferences(tester);
      await tester.tap(find.text('Set a budget'));
      await tester.pump();
      await enterBudget(tester, '7.50');
      await tapDone(tester);

      await tester.tap(find.byKey(const Key('recommendMealButton')));
      await tester.pumpAndSettle();

      final state = tester.state<AgentPageState>(find.byType(AgentPage));
      expect(state.lastRequest!.budgetPerServing, 7.5);
      expect(state.lastRequest!.budget, '7.50');
    });

    testWidgets('generation is blocked while the budget is invalid', (
      tester,
    ) async {
      await pumpAgent(tester, store: FakePreferencesStore());
      await openPreferences(tester);
      await tester.tap(find.text('Set a budget'));
      await tester.pump();
      await enterBudget(tester, 'abc');
      await closeSheet(tester); // swipe-away skips the Done validation

      await tester.tap(find.byKey(const Key('recommendMealButton')));
      await tester.pumpAndSettle();

      expect(bodies, isEmpty);
      // Generate brings the user back to the field with its error showing.
      expect(find.byKey(const Key('agentBudgetField')), findsOneWidget);
      expect(find.textContaining('Enter a budget'), findsOneWidget);
    });
  });
}

AgentRequest _request({
  MealNutritionPreferences nutritionPreferences = MealNutritionPreferences.none,
  double? budgetPerServing,
}) => AgentRequest(
  useFridgeItems: false,
  hasBudget: budgetPerServing != null,
  budget: budgetPerServing?.toString(),
  budgetPerServing: budgetPerServing,
  hasTimeShortage: false,
  timeAvailable: null,
  foodPreferences: 'A quick lunch',
  mealType: MealType.lunch,
  cookingExperience: CookingExperience.beginner,
  recommendationCount: 2,
  fridgeItems: const [],
  feedbackHistory: const [],
  nutritionPreferences: nutritionPreferences,
);

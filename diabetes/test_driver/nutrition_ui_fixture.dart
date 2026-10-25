// Test-only entry point: drives the real AgentPage with in-memory stores and a
// canned Gemini client, so a browser can exercise the nutrition meal picker
// without Firebase, a real account, or paid API calls.
//
//   flutter run -d web-server -t test_driver/nutrition_ui_fixture.dart
//
// Production auth and lib/ are untouched; Firebase.initializeApp is never
// called. Nothing in here ships with the app (it lives outside lib/).
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';

import 'package:diabetes/cgm/data/glucose_repository.dart';
import 'package:diabetes/design/app_theme.dart';
import 'package:diabetes/main.dart';
import 'package:diabetes/meals/data/meal_repository.dart';
import 'package:diabetes/meals/saved/saved_recipe.dart';
import 'package:diabetes/meals/saved/saved_recipes_page.dart';
import 'package:diabetes/meals/saved/saved_recipes_repository.dart';
import 'package:diabetes/meals/services/meal_priority_policy.dart';
import 'package:diabetes/meals/services/meal_qa_service.dart';
import 'package:diabetes/settings/data/app_preferences_repository.dart';
import 'package:diabetes/settings/models/meal_nutrition_preferences.dart';
import 'package:diabetes/ai/ai_retry.dart';
import 'package:diabetes/sleep/data/sleep_repository.dart';
import 'package:diabetes/sleep/models/sleep_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _fixtureUserId = 'fixture-user';

enum FixtureScenario { feasible, conflict, alwaysInvalid }

/// Mutable knobs read by the mock Gemini client on every request.
FixtureScenario _scenario = FixtureScenario.feasible;

/// How many Gemini requests the mock has served (shown in the control bar).
final ValueNotifier<int> _geminiCalls = ValueNotifier<int>(0);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter web paints to a canvas; semantics make it drivable by Playwright.
  SemanticsBinding.instance.ensureSemantics();

  GeminiMealService.debugApiKey = 'fixture-key';
  GeminiMealService.httpClient = MockClient(_handleGemini);
  // Q&A chips would otherwise reach the real Gemini endpoint.
  MealQaService.httpClient = MockClient(
    (request) async => http.Response(
      jsonEncode({
        'error': {'message': 'Q&A is disabled in the UI fixture'},
      }),
      400,
      headers: {'content-type': 'application/json'},
    ),
  );
  AgentPage.retryPolicy = const AiRetryPolicy(
    delay: Duration.zero,
    attemptTimeout: Duration(seconds: 5),
  );

  runApp(const FixtureApp());
}

// ---------------------------------------------------------------------------
// Mock Gemini
// ---------------------------------------------------------------------------

Future<http.Response> _handleGemini(http.Request request) async {
  _geminiCalls.value++;
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final prompt =
      (((body['contents'] as List).first as Map)['parts'] as List).first['text']
          as String;

  final count =
      int.tryParse(
        RegExp(r'exactly (\d+) objects').firstMatch(prompt)?.group(1) ?? '',
      ) ??
      1;
  final budgetMatch = RegExp(r'Budget:\n\$([0-9.]+)').firstMatch(prompt);
  final budget = double.tryParse(budgetMatch?.group(1) ?? '');
  final selectedLabels =
      RegExp(r'Nutrition priorities \(selected: ([^)]*)\)')
          .firstMatch(prompt)
          ?.group(1)
          ?.split(',')
          .map((label) => label.trim())
          .toList() ??
      const <String>[];
  final selectedKeys = [
    for (final label in selectedLabels)
      if (label == MealNutritionPreferences.proteinLabel)
        MealNutritionPreferences.proteinKey
      else if (label == MealNutritionPreferences.carbsLabel)
        MealNutritionPreferences.carbsKey
      else if (label == MealNutritionPreferences.fiberLabel)
        MealNutritionPreferences.fiberKey,
  ];

  final meals = _buildMeals(
    count: count,
    budget: budget,
    selectedKeys: selectedKeys,
    selectedLabels: selectedLabels,
  );
  return http.Response(
    jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode(meals)},
            ],
          },
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

List<Map<String, dynamic>> _buildMeals({
  required int count,
  required double? budget,
  required List<String> selectedKeys,
  required List<String> selectedLabels,
}) {
  final hasPriorities = selectedKeys.isNotEmpty;
  String money(double v) => '\$${v.toStringAsFixed(2)}';

  Map<String, dynamic> meal(
    int index, {
    String? mode,
    double? bound,
    List<String> unmet = const [],
    String? notice,
  }) {
    return {
      'dishName': 'Fixture Dish ${index + 1}${mode == null ? '' : ' ($mode)'}',
      // Empty on purpose: no imageUrl is attached, so the UI never asks the
      // browser to load a photo from the image host.
      'imagePrompt': '',
      'reason': 'Deterministic fixture meal ${index + 1}.',
      'ingredients': [
        'fixture ingredient A${index + 1}',
        'fixture ingredient B',
      ],
      'instructions': ['Step one for dish ${index + 1}.', 'Step two.'],
      'estimatedCostPerServing': bound == null
          ? '\$2-3/serving'
          : '${money(bound)}/serving',
      'estimatedCostUpperBoundPerServing': ?bound,
      if (hasPriorities) ...{
        'priorityMode': mode ?? priorityModeAllPreferences,
        'unmetNutritionPreferences': unmet,
        'constraintNotice': notice,
      },
      'glucoseNote': '',
      'eveningScore': null,
      'usedFridgeItems': <String>[],
      'suggestedQuestions': [
        'Can I swap an ingredient in dish ${index + 1}?',
        'How do I store the leftovers?',
        'Can I make it spicier?',
      ],
    };
  }

  if (_scenario == FixtureScenario.alwaysInvalid) {
    // One meal too many: validateMealResponse rejects it every attempt.
    return [for (var i = 0; i < count + 1; i++) meal(i)];
  }

  final withinBudget = budget == null ? null : budget * 0.8;

  final conflict =
      _scenario == FixtureScenario.conflict && hasPriorities && budget != null;
  if (!conflict) {
    return [
      for (var i = 0; i < count; i++)
        meal(
          i,
          mode: hasPriorities ? priorityModeAllPreferences : null,
          bound: withinBudget,
        ),
    ];
  }

  final limit = budget;
  final overBudget = limit * 1.5;
  final split = fallbackSplit(count);
  final relaxedKey = selectedKeys.last;
  final relaxedLabel = selectedLabels.last;
  return [
    for (var i = 0; i < count; i++)
      // Nutrition-first come first on purpose so the app's budget-first
      // reordering is visible in the browser check.
      if (i >= split.nutritionFirst)
        meal(
          i,
          mode: priorityModeBudgetFirst,
          bound: withinBudget,
          unmet: [relaxedKey],
          notice:
              "We couldn't find a meal meeting all your preferences within "
              '${money(limit)} per serving, so this one relaxes: '
              '$relaxedLabel.',
        )
      else
        meal(
          i,
          mode: priorityModeNutritionFirst,
          bound: overBudget,
          notice:
              'This meal keeps all your nutrition preferences but costs up '
              'to ${money(overBudget)} per serving, over your '
              '${money(limit)} budget.',
        ),
  ];
}

// ---------------------------------------------------------------------------
// In-memory stores
// ---------------------------------------------------------------------------

/// [AppPreferencesStore] with no Firestore: every watch replays its current
/// value to new listeners, and the next nutrition save can be made to fail.
class FixturePreferencesStore implements AppPreferencesStore {
  final ValueNotifier<bool> failNextNutritionSave = ValueNotifier(false);
  final ValueNotifier<MealNutritionPreferences> savedNutrition = ValueNotifier(
    MealNutritionPreferences.none,
  );
  int nutritionSaveAttempts = 0;

  final _balance = _Replay<bool>(false);
  final _qaTip = _Replay<bool>(false);
  final _guide = _Replay<bool>(false);
  late final _nutrition = _Replay<MealNutritionPreferences>(
    MealNutritionPreferences.none,
  );

  @override
  Stream<bool> watchMealBalanceAgentEnabled(String userId) => _balance.watch();

  @override
  Future<void> saveMealBalanceAgentEnabled(String userId, bool enabled) async =>
      _balance.set(enabled);

  @override
  Stream<bool> watchMealQaTipSeen(String userId) => _qaTip.watch();

  @override
  Future<void> saveMealQaTipSeen(String userId) async => _qaTip.set(true);

  @override
  Stream<bool> watchFirstMealGuidePending(String userId) => _guide.watch();

  @override
  Future<void> completeFirstMealGuide(String userId) async => _guide.set(false);

  @override
  Stream<MealNutritionPreferences> watchMealNutritionPreferences(
    String userId,
  ) => _nutrition.watch();

  @override
  Future<void> saveMealNutritionPreferences(
    String userId,
    MealNutritionPreferences preferences,
  ) async {
    nutritionSaveAttempts++;
    // Yield once so the UI's "saving" state is observable.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (failNextNutritionSave.value) {
      failNextNutritionSave.value = false;
      throw Exception('Fixture: nutrition save failed');
    }
    savedNutrition.value = preferences;
    _nutrition.set(preferences);
  }
}

/// A value plus broadcast of changes; each new listener first gets the
/// current value.
class _Replay<T> {
  _Replay(this._value);

  T _value;
  final List<StreamController<T>> _listeners = [];

  Stream<T> watch() {
    late StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        _listeners.add(controller);
        controller.add(_value);
      },
      onCancel: () => _listeners.remove(controller),
    );
    return controller.stream;
  }

  void set(T value) {
    _value = value;
    for (final controller in List.of(_listeners)) {
      controller.add(value);
    }
  }
}

class FixtureSavedRecipesStore implements SavedRecipesStore {
  FixtureSavedRecipesStore() {
    _items = [
      // With tradeoff metadata.
      SavedRecipe(
        id: recipeFingerprint(_withMetadata),
        recipe: _withMetadata,
        savedAt: DateTime(2026, 1, 2),
      ),
      // Legacy: saved before priorityMode / budget metadata existed.
      SavedRecipe(
        id: recipeFingerprint(_legacy),
        recipe: _legacy,
        savedAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  static const _withMetadata = MealRecommendation(
    dishName: 'Seeded Budget-First Lentil Bowl',
    imagePrompt: '',
    reason: 'Pre-seeded recipe that carries tradeoff metadata.',
    ingredients: ['lentils', 'rice'],
    instructions: ['Simmer lentils.', 'Serve over rice.'],
    estimatedCostPerServing: r'$2.40/serving',
    estimatedCostUpperBoundPerServing: 2.4,
    priorityMode: priorityModeBudgetFirst,
    unmetNutritionPreferences: ['protein'],
    constraintNotice:
        "We couldn't find a meal meeting all your preferences within "
        r'$3.00 per serving, so this one relaxes: High protein.',
    requestBudgetPerServing: 3.0,
  );

  static const _legacy = MealRecommendation(
    dishName: 'Seeded Legacy Omelette',
    imagePrompt: '',
    reason: 'Pre-seeded recipe saved before nutrition priorities existed.',
    ingredients: ['eggs', 'spinach'],
    instructions: ['Whisk eggs.', 'Cook with spinach.'],
    estimatedCostPerServing: r'$1-2/serving',
  );

  late List<SavedRecipe> _items;
  final List<StreamController<List<SavedRecipe>>> _listeners = [];

  @override
  Stream<List<SavedRecipe>> watchAll(String userId) {
    late StreamController<List<SavedRecipe>> controller;
    controller = StreamController<List<SavedRecipe>>(
      onListen: () {
        _listeners.add(controller);
        controller.add(List.of(_items));
      },
      onCancel: () => _listeners.remove(controller),
    );
    return controller.stream;
  }

  @override
  Future<void> save(String userId, MealRecommendation recipe) async {
    final id = recipeFingerprint(recipe);
    _items = [
      SavedRecipe(id: id, recipe: recipe, savedAt: DateTime.now()),
      ..._items.where((item) => item.id != id),
    ];
    _emit();
  }

  @override
  Future<void> remove(String userId, String recipeId) async {
    _items = _items.where((item) => item.id != recipeId).toList();
    _emit();
  }

  void _emit() {
    for (final controller in List.of(_listeners)) {
      controller.add(List.of(_items));
    }
  }
}

// `implements` skips the Firestore-backed constructors, so no Firebase app is
// needed. Only what AgentPage's overnight lookup touches is real; sleep logs
// are empty, which makes the lookup return before it reads glucose or meals.
class _FixtureSleepRepository implements SleepRepository {
  @override
  Stream<List<SleepLog>> watchRecentSleep(String userId, {int limit = 30}) =>
      Stream.value(const <SleepLog>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Fixture sleep repository: $invocation');
}

class _FixtureGlucoseRepository implements GlucoseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Fixture glucose repository: $invocation');
}

class _FixtureMealRepository implements MealRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Fixture meal repository: $invocation');
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class FixtureApp extends StatelessWidget {
  const FixtureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nutrition UI fixture',
      theme: AppTheme.light(),
      home: const FixtureHome(),
    );
  }
}

class FixtureHome extends StatefulWidget {
  const FixtureHome({super.key});

  @override
  State<FixtureHome> createState() => _FixtureHomeState();
}

class _FixtureHomeState extends State<FixtureHome> {
  // Survive remounts, like the real account's Firestore documents would.
  final _preferences = FixturePreferencesStore();
  final _savedRecipes = FixtureSavedRecipesStore();
  final _sleep = _FixtureSleepRepository();
  final _glucose = _FixtureGlucoseRepository();
  final _meals = _FixtureMealRepository();

  bool _diabetes = false;
  int _mountCount = 0;

  void _remount() => setState(() => _mountCount++);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _controlBar(context),
            const Divider(height: 1),
            Expanded(
              child: AgentPage(
                key: ValueKey('fixtureAgentPage-$_mountCount'),
                foodItems: const [],
                userId: _fixtureUserId,
                geminiApiKey: 'fixture-key',
                sleepRepository: _sleep,
                glucoseRepository: _glucose,
                mealRepository: _meals,
                diabetesEnabled: _diabetes,
                preferencesRepository: _preferences,
                savedRecipesStore: _savedRecipes,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('FIXTURE'),
          ChoiceChip(
            key: const Key('fixtureScenarioFeasible'),
            label: const Text('Feasible'),
            selected: _scenario == FixtureScenario.feasible,
            onSelected: (_) =>
                setState(() => _scenario = FixtureScenario.feasible),
          ),
          ChoiceChip(
            key: const Key('fixtureScenarioConflict'),
            label: const Text('Conflict'),
            selected: _scenario == FixtureScenario.conflict,
            onSelected: (_) =>
                setState(() => _scenario = FixtureScenario.conflict),
          ),
          ChoiceChip(
            key: const Key('fixtureScenarioAlwaysInvalid'),
            label: const Text('Always invalid'),
            selected: _scenario == FixtureScenario.alwaysInvalid,
            onSelected: (_) =>
                setState(() => _scenario = FixtureScenario.alwaysInvalid),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _preferences.failNextNutritionSave,
            builder: (context, value, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Fail next nutrition save'),
                Switch(
                  key: const Key('fixtureFailNextSave'),
                  value: value,
                  onChanged: (v) =>
                      _preferences.failNextNutritionSave.value = v,
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_diabetes ? 'Diabetes on' : 'Diabetes off'),
              Switch(
                key: const Key('fixtureDiabetes'),
                value: _diabetes,
                // AgentPage reads diabetesEnabled in initState, so remount.
                onChanged: (v) => setState(() {
                  _diabetes = v;
                  _mountCount++;
                }),
              ),
            ],
          ),
          OutlinedButton(
            key: const Key('fixtureRemount'),
            onPressed: _remount,
            child: const Text('Remount picker'),
          ),
          OutlinedButton(
            key: const Key('fixtureOpenSavedRecipes'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => SavedRecipesPage(
                  userId: _fixtureUserId,
                  store: _savedRecipes,
                  geminiApiKey: 'fixture-key',
                  diabetesEnabled: _diabetes,
                  preferencesRepository: _preferences,
                  onOpenMeals: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            child: const Text('Open saved recipes'),
          ),
          ValueListenableBuilder<int>(
            valueListenable: _geminiCalls,
            builder: (context, calls, _) => Text(
              'Gemini calls: $calls',
              key: const Key('fixtureGeminiCalls'),
            ),
          ),
          ValueListenableBuilder<MealNutritionPreferences>(
            valueListenable: _preferences.savedNutrition,
            builder: (context, saved, _) => Text(
              'Saved priorities: '
              '${saved.hasAny ? saved.selectedKeys.join(',') : 'none'}',
              key: const Key('fixtureSavedPriorities'),
            ),
          ),
        ],
      ),
    );
  }
}

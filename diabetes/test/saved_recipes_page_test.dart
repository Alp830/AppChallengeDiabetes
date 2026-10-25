import 'package:diabetes/design/app_theme.dart';
import 'package:diabetes/main.dart';
import 'package:diabetes/meals/saved/saved_recipe.dart';
import 'package:diabetes/meals/saved/saved_recipes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_preferences_store.dart';
import 'support/in_memory_saved_recipes_store.dart';

MealRecommendation _recipe({String dishName = 'Lemon chicken bowl'}) {
  return MealRecommendation(
    dishName: dishName,
    imagePrompt: 'a $dishName',
    reason: 'Quick and uses pantry basics.',
    ingredients: const ['1 lemon', '200g chicken'],
    instructions: const ['Cook the rice.', 'Grill the chicken.'],
    usedFridgeItems: const ['Chicken'],
    estimatedCostPerServing: r'$3/serving',
  );
}

SavedRecipe _saved(MealRecommendation recipe, {DateTime? savedAt}) =>
    SavedRecipe(
      id: recipeFingerprint(recipe),
      recipe: recipe,
      savedAt: savedAt ?? DateTime(2026, 9, 28, 10),
    );

void main() {
  late http.Client originalClient;
  var httpCalls = 0;

  setUp(() {
    originalClient = GeminiMealService.httpClient;
    httpCalls = 0;
    // Any AI request during these tests is a bug: a saved recipe must open
    // from stored data alone.
    GeminiMealService.httpClient = MockClient((request) async {
      httpCalls++;
      return http.Response('should never be called', 500);
    });
  });

  tearDown(() => GeminiMealService.httpClient = originalClient);

  Future<void> pumpList(
    WidgetTester tester, {
    required InMemorySavedRecipesStore store,
    VoidCallback? onOpenMeals,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SavedRecipesPage(
          userId: 'user-1',
          store: store,
          diabetesEnabled: false,
          preferencesRepository: FakePreferencesStore(mealQaTipSeen: true),
          onOpenMeals: onOpenMeals,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the empty state points the user to Meals', (tester) async {
    var openedMeals = 0;
    await pumpList(
      tester,
      store: InMemorySavedRecipesStore(),
      onOpenMeals: () => openedMeals++,
    );

    expect(find.text('No saved recipes yet'), findsOneWidget);
    expect(
      find.text('Save a recipe from Meals and it will show up here.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('savedRecipesGoToMeals')));
    expect(openedMeals, 1);
  });

  testWidgets('recipes are listed newest first with their saved date', (
    tester,
  ) async {
    final store = InMemorySavedRecipesStore(
      initial: [
        _saved(_recipe(dishName: 'Older dish'), savedAt: DateTime(2026, 9, 20)),
        _saved(_recipe(dishName: 'Newer dish'), savedAt: DateTime(2026, 9, 27)),
      ],
    );
    await pumpList(tester, store: store);

    final newerY = tester.getTopLeft(find.text('Newer dish')).dy;
    final olderY = tester.getTopLeft(find.text('Older dish')).dy;
    expect(newerY, lessThan(olderY));
    expect(find.textContaining(RegExp(r'^Saved \w+ \d+$')), findsNWidgets(2));
    expect(find.byIcon(Icons.restaurant_menu), findsNWidgets(2));
  });

  testWidgets('opening a saved recipe shows the full recipe with no AI call', (
    tester,
  ) async {
    final store = InMemorySavedRecipesStore(initial: [_saved(_recipe())]);
    await pumpList(tester, store: store);

    await tester.tap(find.byKey(const Key('savedRecipe_0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('savedRecipeDetail')), findsOneWidget);
    expect(find.text('1 lemon'), findsOneWidget);
    expect(find.text('200g chicken'), findsOneWidget);
    expect(find.text('Cook the rice.'), findsOneWidget);
    expect(find.text('Grill the chicken.'), findsOneWidget);
    expect(find.text('Quick and uses pantry basics.'), findsOneWidget);
    expect(httpCalls, 0, reason: 'a saved recipe opens from stored data');
  });

  testWidgets('a saved recipe keeps its notice and budget-fit phrasing', (
    tester,
  ) async {
    const recipe = MealRecommendation(
      dishName: 'Lentil stew',
      imagePrompt: '',
      reason: 'Hearty.',
      ingredients: ['Lentils'],
      instructions: ['Simmer.'],
      priorityMode: 'budgetFirst',
      unmetNutritionPreferences: ['fiber'],
      constraintNotice: 'Kept the cost low.',
      estimatedCostUpperBoundPerServing: 6,
      requestBudgetPerServing: 5,
    );
    final store = InMemorySavedRecipesStore(initial: [_saved(recipe)]);
    await pumpList(tester, store: store);
    await tester.tap(find.byKey(const Key('savedRecipe_0')));
    await tester.pumpAndSettle();

    expect(find.text('Kept the cost low.'), findsOneWidget);
    expect(find.text('Budget-first option'), findsOneWidget);
    expect(find.text('Relaxed: High fiber'), findsOneWidget);
    expect(
      find.textContaining(
        r'Budget fit is from when this was suggested ($5 per serving)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a saved recipe without metadata shows no tradeoff notes', (
    tester,
  ) async {
    final store = InMemorySavedRecipesStore(initial: [_saved(_recipe())]);
    await pumpList(tester, store: store);
    await tester.tap(find.byKey(const Key('savedRecipe_0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mealCostEstimatesNote')), findsNothing);
    expect(find.byKey(const Key('mealPriorityModeLabel')), findsNothing);
  });

  testWidgets('the saved recipe view hides the balancing tweak', (
    tester,
  ) async {
    final store = InMemorySavedRecipesStore(initial: [_saved(_recipe())]);
    await pumpList(tester, store: store);
    await tester.tap(find.byKey(const Key('savedRecipe_0')));
    await tester.pumpAndSettle();

    expect(find.text('Add a balancing tweak'), findsNothing);
    expect(find.byKey(const Key('recipeUnsaveButton')), findsOneWidget);
  });

  testWidgets('removing from the detail view pops back and updates the list', (
    tester,
  ) async {
    final store = InMemorySavedRecipesStore(initial: [_saved(_recipe())]);
    await pumpList(tester, store: store);
    await tester.tap(find.byKey(const Key('savedRecipe_0')));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('savedRecipeDetail')),
      const Offset(0, -3000),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('recipeUnsaveButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('savedRecipeDetail')), findsNothing);
    expect(find.text('No saved recipes yet'), findsOneWidget);
    expect(find.text('Removed from saved recipes'), findsOneWidget);
    expect(store.recipes, isEmpty);

    // Undo puts it back under the same id.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.recipes, hasLength(1));
    expect(find.text('Lemon chicken bowl'), findsOneWidget);
  });

  testWidgets('a stream failure shows a friendly error with retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var subscriptions = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SavedRecipesPage(
          userId: 'user-1',
          diabetesEnabled: false,
          store: _FailingStore(onWatch: () => subscriptions++),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load your saved recipes."), findsOneWidget);
    await tester.tap(find.byKey(const Key('loadErrorRetry')));
    await tester.pumpAndSettle();
    expect(subscriptions, 2);
  });
}

class _FailingStore extends InMemorySavedRecipesStore {
  _FailingStore({required this.onWatch});

  final VoidCallback onWatch;

  @override
  Stream<List<SavedRecipe>> watchAll(String userId) {
    onWatch();
    return Stream<List<SavedRecipe>>.error(Exception('offline'));
  }
}

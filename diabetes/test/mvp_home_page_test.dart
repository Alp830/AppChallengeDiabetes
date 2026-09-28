import 'package:diabetes/exercise/data/today_todo_repository.dart';
import 'package:diabetes/home/mvp_home_page.dart';
import 'package:diabetes/main.dart' show MealRecommendation;
import 'package:diabetes/meals/saved/saved_recipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/in_memory_saved_recipes_store.dart';

SavedRecipe _savedRecipe(String dishName) {
  final recipe = MealRecommendation(
    dishName: dishName,
    imagePrompt: '',
    reason: 'Quick.',
    ingredients: const ['Rice'],
    instructions: const ['Cook it.'],
  );
  return SavedRecipe(
    id: recipeFingerprint(recipe),
    recipe: recipe,
    savedAt: DateTime(2026, 9, 28),
  );
}

void main() {
  testWidgets('MVP home opens the fridge and manages the daily checklist', (
    tester,
  ) async {
    var fridgeOpenCount = 0;
    var savedItems = <TodayTodo>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MvpHomePage(
            userId: 'user-1',
            userName: 'Lina',
            now: DateTime(2026, 7, 21),
            todoStateStream: Stream.value(
              const TodayTodoState(isInitialized: true, items: []),
            ),
            onSaveTodos: (items) async => savedItems = List.of(items),
            onOpenFridge: () => fridgeOpenCount++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('mvpHomePage')), findsOneWidget);
    expect(find.text('No tasks yet'), findsOneWidget);

    await tester.tap(find.text("What's in your fridge"));
    expect(fridgeOpenCount, 1);

    await tester.tap(find.byKey(const Key('mvpAddTodoButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('mvpTodoNameField')),
      'Check fridge',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Check fridge'), findsOneWidget);
    expect(savedItems.single.name, 'Check fridge');

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(savedItems.single.isCompleted, isTrue);

    await tester.tap(find.byTooltip('Remove Check fridge'));
    await tester.pump();
    expect(savedItems, isEmpty);
    await tester.pumpAndSettle(); // snackbar appears after the async save
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(savedItems.single.name, 'Check fridge');
  });

  Widget home({
    required Stream<TodayTodoState> stream,
    int? fridgeItemCount,
    int expiringCount = 0,
  }) => MaterialApp(
    home: Scaffold(
      body: MvpHomePage(
        userId: 'user-1',
        now: DateTime(2026, 7, 21),
        todoStateStream: stream,
        onSaveTodos: (_) async {},
        onOpenFridge: () {},
        fridgeItemCount: fridgeItemCount,
        expiringCount: expiringCount,
      ),
    ),
  );

  testWidgets('banner summarizes the fridge', (tester) async {
    await tester.pumpWidget(
      home(
        stream: Stream.value(
          const TodayTodoState(isInitialized: true, items: []),
        ),
        fridgeItemCount: 5,
        expiringCount: 2,
      ),
    );
    await tester.pump();
    expect(find.text('5 items · 2 expiring soon'), findsOneWidget);
  });

  testWidgets('tapping a task opens the edit dialog', (tester) async {
    await tester.pumpWidget(
      home(
        stream: Stream.value(
          const TodayTodoState(
            isInitialized: true,
            items: [TodayTodo(id: 't1', name: 'Walk')],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Walk'));
    await tester.pumpAndSettle();
    expect(find.text('Edit task'), findsOneWidget);
  });

  testWidgets('loading shows a skeleton, errors offer retry', (tester) async {
    await tester.pumpWidget(home(stream: const Stream<TodayTodoState>.empty()));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading your checklist'), findsOneWidget);

    // Unmount first: the page reads its stream once, in initState.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(home(stream: Stream.error(Exception('offline'))));
    await tester.pump();
    expect(find.byKey(const Key('loadErrorRetry')), findsOneWidget);
  });

  Widget homeWithExtras({
    bool showFirstMealGuide = false,
    VoidCallback? onStartFirstMeal,
    VoidCallback? onSkipFirstMeal,
    InMemorySavedRecipesStore? savedRecipesStore,
    VoidCallback? onOpenSavedRecipes,
  }) => MaterialApp(
    home: Scaffold(
      body: MvpHomePage(
        userId: 'user-1',
        now: DateTime(2026, 7, 21),
        todoStateStream: Stream.value(
          const TodayTodoState(isInitialized: true, items: []),
        ),
        onSaveTodos: (_) async {},
        onOpenFridge: () {},
        fridgeItemCount: 0,
        showFirstMealGuide: showFirstMealGuide,
        onStartFirstMeal: onStartFirstMeal,
        onSkipFirstMeal: onSkipFirstMeal,
        savedRecipesStore: savedRecipesStore,
        onOpenSavedRecipes: onOpenSavedRecipes,
      ),
    ),
  );

  testWidgets('the first-meal card leads with one tap and can be skipped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var started = 0;
    var skipped = 0;

    await tester.pumpWidget(
      homeWithExtras(
        showFirstMealGuide: true,
        onStartFirstMeal: () => started++,
        onSkipFirstMeal: () => skipped++,
      ),
    );
    await tester.pump();

    expect(find.text("Let's get started"), findsOneWidget);
    expect(
      find.text(
        'Get your first meal idea in under a minute. No need to fill your '
        'fridge first.',
      ),
      findsOneWidget,
    );
    expect(find.text('Tap Recommend a meal'), findsOneWidget);
    // It sits above the fridge banner: the first meal comes before stocking up.
    expect(
      tester.getTopLeft(find.text("Let's get started")).dy,
      lessThan(tester.getTopLeft(find.text("What's in your fridge")).dy),
    );

    await tester.tap(find.byKey(const Key('firstMealStart')));
    expect(started, 1);
    await tester.tap(find.byKey(const Key('firstMealSkip')));
    expect(skipped, 1);
  });

  testWidgets('a returning user sees no first-meal card', (tester) async {
    await tester.pumpWidget(
      homeWithExtras(onStartFirstMeal: () {}, onSkipFirstMeal: () {}),
    );
    await tester.pump();

    expect(find.text("Let's get started"), findsNothing);
    expect(find.byKey(const Key('firstMealStart')), findsNothing);
  });

  testWidgets('the saved recipes card previews the list and opens it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var opened = 0;
    final store = InMemorySavedRecipesStore(
      initial: [
        _savedRecipe('Lemon chicken bowl'),
        _savedRecipe('Tomato pasta'),
        _savedRecipe('Oat pancakes'),
      ],
    );

    await tester.pumpWidget(
      homeWithExtras(
        savedRecipesStore: store,
        onOpenSavedRecipes: () => opened++,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved recipes'), findsOneWidget);
    expect(find.textContaining('3 saved · '), findsOneWidget);

    await tester.tap(find.byKey(const Key('homeSavedRecipes')));
    expect(opened, 1);
  });

  testWidgets('the saved recipes card explains itself when empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      homeWithExtras(
        savedRecipesStore: InMemorySavedRecipesStore(),
        onOpenSavedRecipes: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Save recipes from Meals to cook them again'),
      findsOneWidget,
    );
  });

  testWidgets('the saved recipes card is hidden without a handler', (
    tester,
  ) async {
    await tester.pumpWidget(homeWithExtras());
    await tester.pump();

    expect(find.byKey(const Key('homeSavedRecipes')), findsNothing);
  });
}

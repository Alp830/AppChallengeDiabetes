import 'package:diabetes/design/app_theme.dart';
import 'package:diabetes/exercise/data/today_todo_repository.dart';
import 'package:diabetes/home/mvp_home_page.dart';
import 'package:diabetes/main.dart';
import 'package:diabetes/meals/saved/saved_recipe.dart';
import 'package:diabetes/meals/saved/saved_recipes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/in_memory_saved_recipes_store.dart';

Future<void> pumpAt200(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(body: body),
    ),
  );
  await tester.pump();
}

SavedRecipe _savedRecipe() {
  const recipe = MealRecommendation(
    dishName: 'Spinach and feta omelette with roasted tomatoes',
    imagePrompt: '',
    reason: 'Uses the spinach before it expires.',
    ingredients: ['2 eggs', '1 cup spinach'],
    instructions: ['Whisk the eggs.', 'Cook with spinach.'],
  );
  return SavedRecipe(
    id: recipeFingerprint(recipe),
    recipe: recipe,
    savedAt: DateTime(2026, 9, 28),
  );
}

StoredFoodItem _stored(String id, String name, int days) => StoredFoodItem(
  id: id,
  foodItem: FoodItem(
    name: name,
    amount: '1',
    foodType: FoodType.dairy,
    expiryDate: DateTime.now().add(Duration(days: days)),
  ),
);

void main() {
  testWidgets('Home', (tester) async {
    await pumpAt200(
      tester,
      MvpHomePage(
        userId: 'u',
        userName: 'Alexandria',
        todoStateStream: Stream.value(
          const TodayTodoState(
            isInitialized: true,
            items: [TodayTodo(id: 't', name: 'Prep lunch for tomorrow')],
          ),
        ),
        onSaveTodos: (_) async {},
        onOpenFridge: () {},
        fridgeItemCount: 12,
        expiringCount: 3,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home with the first-meal and saved recipes cards', (
    tester,
  ) async {
    await pumpAt200(
      tester,
      MvpHomePage(
        userId: 'u',
        userName: 'Alexandria',
        todoStateStream: Stream.value(
          const TodayTodoState(isInitialized: true, items: []),
        ),
        onSaveTodos: (_) async {},
        onOpenFridge: () {},
        fridgeItemCount: 12,
        expiringCount: 3,
        showFirstMealGuide: true,
        onStartFirstMeal: () {},
        onSkipFirstMeal: () {},
        savedRecipesStore: InMemorySavedRecipesStore(initial: [_savedRecipe()]),
        onOpenSavedRecipes: () {},
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text("Let's get started"), findsOneWidget);
  });

  testWidgets('Saved recipes list', (tester) async {
    await pumpAt200(
      tester,
      SavedRecipesPage(
        userId: 'u',
        diabetesEnabled: false,
        store: InMemorySavedRecipesStore(initial: [_savedRecipe()]),
        onOpenMeals: () {},
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Saved recipes empty state', (tester) async {
    await pumpAt200(
      tester,
      SavedRecipesPage(
        userId: 'u',
        diabetesEnabled: false,
        store: InMemorySavedRecipesStore(),
        onOpenMeals: () {},
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fridge grid', (tester) async {
    await pumpAt200(
      tester,
      FridgePage(
        initialItems: [
          _stored('a', 'Greek yogurt', 1),
          _stored('b', 'Chicken thighs', 5),
          _stored('c', 'Spinach', -1),
        ],
        onCommit: (_) async {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Greek yogurt'), findsOneWidget);
  });

  testWidgets('Fridge empty state', (tester) async {
    await pumpAt200(
      tester,
      FridgePage(initialItems: const [], onCommit: (_) async {}),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Agent', (tester) async {
    await pumpAt200(tester, const AgentPage(foodItems: []));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Agent with the first-meal coach', (tester) async {
    await pumpAt200(
      tester,
      const AgentPage(foodItems: [], firstMealGuide: true),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Your first meal idea'), findsOneWidget);
  });

  testWidgets('Recipe card', (tester) async {
    await pumpAt200(
      tester,
      ListView(
        children: [
          MealRecommendationCard(
            recommendation: const MealRecommendation(
              dishName: 'Spinach and feta omelette',
              imagePrompt: '',
              reason: 'Uses the spinach before it expires.',
              ingredients: ['2 eggs', '1 cup spinach'],
              instructions: ['Whisk the eggs.', 'Cook with spinach.'],
              estimatedCostPerServing: r'$2-3/serving',
            ),
            diabetesEnabled: false,
            timeLabel: '≤ 20 min',
            difficultyLabel: 'Beginner',
            onLogMeal: () {},
            onMakeBalanced: () {},
            onAsk: (scope, {String? initialQuestion}) {},
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

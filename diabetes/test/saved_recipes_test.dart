import 'package:diabetes/main.dart';
import 'package:diabetes/meals/saved/saved_recipe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/in_memory_saved_recipes_store.dart';

MealRecommendation _recipe({
  String dishName = 'Lemon chicken bowl',
  List<String> ingredients = const ['1 lemon', '200g chicken', 'Rice'],
}) {
  return MealRecommendation(
    dishName: dishName,
    imagePrompt: 'A lemon chicken bowl',
    reason: 'Uses the chicken before it expires.',
    ingredients: ingredients,
    instructions: const ['Cook the rice.', 'Grill the chicken.'],
    glucoseNote: 'Pair with the salad for a gentler rise.',
    eveningScore: 4,
    usedFridgeItems: const ['Chicken'],
    estimatedCostPerServing: r'$3/serving',
    suggestedQuestions: const ['Can I swap the rice?'],
    imageUrl: 'https://example.test/lemon.png',
  );
}

void main() {
  group('MealRecommendation JSON round trip', () {
    test('keeps every field, including the image URL', () {
      final original = _recipe();

      final restored = MealRecommendation.fromJson(original.toJson());

      expect(restored.dishName, original.dishName);
      expect(restored.imagePrompt, original.imagePrompt);
      expect(restored.reason, original.reason);
      expect(restored.ingredients, original.ingredients);
      expect(restored.instructions, original.instructions);
      expect(restored.glucoseNote, original.glucoseNote);
      expect(restored.eveningScore, original.eveningScore);
      expect(restored.usedFridgeItems, original.usedFridgeItems);
      expect(
        restored.estimatedCostPerServing,
        original.estimatedCostPerServing,
      );
      expect(restored.suggestedQuestions, original.suggestedQuestions);
      expect(restored.imageUrl, original.imageUrl);
    });

    test('optional fields stay null through the round trip', () {
      const original = MealRecommendation(
        dishName: 'Oatmeal',
        imagePrompt: '',
        reason: 'Fast.',
        ingredients: ['Oats'],
        instructions: ['Stir.'],
      );

      final restored = MealRecommendation.fromJson(original.toJson());

      expect(restored.glucoseNote, isNull);
      expect(restored.eveningScore, isNull);
      expect(restored.estimatedCostPerServing, isNull);
      expect(restored.imageUrl, isNull);
      expect(restored.usedFridgeItems, isEmpty);
      expect(restored.suggestedQuestions, isEmpty);
    });
  });

  group('budget tradeoff metadata', () {
    test('round trips every tradeoff field', () {
      const original = MealRecommendation(
        dishName: 'Lentil stew',
        imagePrompt: '',
        reason: 'Cheap.',
        ingredients: ['Lentils'],
        instructions: ['Simmer.'],
        priorityMode: 'budgetFirst',
        unmetNutritionPreferences: ['protein'],
        constraintNotice: 'Kept it cheap.',
        estimatedCostUpperBoundPerServing: 4.5,
        requestBudgetPerServing: 4,
      );

      final restored = MealRecommendation.fromJson(original.toJson());

      expect(restored.priorityMode, 'budgetFirst');
      expect(restored.unmetNutritionPreferences, ['protein']);
      expect(restored.constraintNotice, 'Kept it cheap.');
      expect(restored.estimatedCostUpperBoundPerServing, 4.5);
      expect(restored.requestBudgetPerServing, 4);
      expect(original.copyWith(imageUrl: 'x').requestBudgetPerServing, 4);
    });

    test('an old saved recipe without the fields still loads', () {
      final restored = MealRecommendation.fromJson({
        'dishName': 'Oatmeal',
        'reason': 'Fast.',
        'ingredients': ['Oats'],
        'instructions': ['Stir.'],
      });

      expect(restored.requestBudgetPerServing, isNull);
      expect(restored.priorityMode, isNull);
      expect(restored.toJson().containsKey('requestBudgetPerServing'), false);
    });
  });

  group('recipeFingerprint', () {
    test('ignores ingredient order, case, and extra whitespace', () {
      final a = _recipe(ingredients: const ['1 lemon', '200g chicken', 'Rice']);
      final b = _recipe(
        dishName: '  lemon   Chicken bowl ',
        ingredients: const ['RICE', '  1 Lemon', '200g  chicken'],
      );

      expect(recipeFingerprint(a), recipeFingerprint(b));
    });

    test('changes when an ingredient changes', () {
      expect(
        recipeFingerprint(_recipe()),
        isNot(
          recipeFingerprint(
            _recipe(ingredients: const ['1 lime', '200g chicken', 'Rice']),
          ),
        ),
      );
    });

    test('changes when the dish name changes', () {
      expect(
        recipeFingerprint(_recipe()),
        isNot(recipeFingerprint(_recipe(dishName: 'Lime chicken bowl'))),
      );
    });

    test('is 16 hex characters', () {
      expect(recipeFingerprint(_recipe()), matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });

  group('saved recipes store', () {
    test('saving the same recipe twice keeps one entry', () async {
      final store = InMemorySavedRecipesStore();

      await store.save('u1', _recipe());
      await store.save(
        'u1',
        _recipe(ingredients: const ['Rice', '1 LEMON', '200g chicken']),
      );

      expect(store.recipes, hasLength(1));
      expect(store.recipes.single.id, recipeFingerprint(_recipe()));
    });

    test('watchAll emits newest first and updates on remove', () async {
      final store = InMemorySavedRecipesStore();
      final emissions = <List<SavedRecipe>>[];
      final subscription = store.watchAll('u1').listen(emissions.add);

      await store.save('u1', _recipe(dishName: 'First dish'));
      await store.save('u1', _recipe(dishName: 'Second dish'));
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last.map((saved) => saved.recipe.dishName), [
        'Second dish',
        'First dish',
      ]);

      await store.remove('u1', emissions.last.first.id);
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last.map((saved) => saved.recipe.dishName), [
        'First dish',
      ]);
      await subscription.cancel();
    });

    test('SavedRecipe survives a Firestore-shaped round trip', () {
      final saved = SavedRecipe(
        id: 'abc',
        recipe: _recipe(),
        savedAt: DateTime(2026, 9, 28, 9, 30),
      );

      final restored = SavedRecipe.fromMap('abc', {
        'recipe': saved.recipe.toJson(),
        'savedAt': saved.savedAt,
      });

      expect(restored.id, 'abc');
      expect(restored.recipe.dishName, 'Lemon chicken bowl');
      expect(restored.recipe.instructions, hasLength(2));
      expect(restored.savedAt, DateTime(2026, 9, 28, 9, 30));
    });
  });
}

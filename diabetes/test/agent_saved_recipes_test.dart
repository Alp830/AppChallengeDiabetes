import 'dart:convert';

import 'package:diabetes/main.dart';
import 'package:diabetes/meals/saved/saved_recipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_preferences_store.dart';
import 'support/in_memory_saved_recipes_store.dart';

/// One recommendation, as Gemini would return it.
String _modelReply({String dishName = 'Lemon chicken bowl'}) => jsonEncode({
  'candidates': [
    {
      'content': {
        'parts': [
          {
            'text': jsonEncode([
              {
                'dishName': dishName,
                'imagePrompt': 'a $dishName',
                'reason': 'Quick and uses pantry basics.',
                'ingredients': ['1 lemon', 'Rice'],
                'instructions': ['Cook the rice.', 'Squeeze the lemon.'],
              },
            ]),
          },
        ],
      },
    },
  ],
});

void main() {
  late http.Client originalClient;

  setUp(() {
    originalClient = GeminiMealService.httpClient;
    AppEnvironment.setGeminiApiKeyForTesting('test-key');
  });

  tearDown(() {
    GeminiMealService.httpClient = originalClient;
    AppEnvironment.setGeminiApiKeyForTesting('');
  });

  Future<void> pumpAgent(
    WidgetTester tester, {
    required InMemorySavedRecipesStore savedRecipes,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentPage(
            foodItems: const [],
            userId: 'user-1',
            geminiApiKey: 'test-key',
            diabetesEnabled: false,
            preferencesRepository: FakePreferencesStore(),
            savedRecipesStore: savedRecipes,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> recommend(WidgetTester tester) async {
    // Scroll back to the top: the button is above the results.
    await tester.drag(find.byType(ListView).first, const Offset(0, 4000));
    await tester.pump();
    await tester.tap(find.byKey(const Key('recommendMealButton')));
    await tester.pumpAndSettle();
  }

  Future<void> scrollToActions(WidgetTester tester) async {
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pump();
  }

  testWidgets('Save recipe stores the recipe once and flips to Saved', (
    tester,
  ) async {
    GeminiMealService.httpClient = MockClient(
      (request) async => http.Response(_modelReply(), 200),
    );
    final savedRecipes = InMemorySavedRecipesStore();
    await pumpAgent(tester, savedRecipes: savedRecipes);
    await recommend(tester);

    expect(find.text('Lemon chicken bowl'), findsOneWidget);

    await scrollToActions(tester);
    await tester.tap(find.byKey(const Key('recipeSaveButton')));
    await tester.pumpAndSettle();

    expect(savedRecipes.saveCalls, 1);
    expect(savedRecipes.recipes.single.recipe.dishName, 'Lemon chicken bowl');
    expect(savedRecipes.recipes.single.recipe.instructions, [
      'Cook the rice.',
      'Squeeze the lemon.',
    ]);
    expect(
      find.text('Saved. Find it on Home under Saved recipes.'),
      findsOneWidget,
    );

    await scrollToActions(tester);
    expect(find.byKey(const Key('recipeUnsaveButton')), findsOneWidget);
    expect(find.byKey(const Key('recipeSaveButton')), findsNothing);
  });

  testWidgets('a recipe already saved opens as Saved and can be removed', (
    tester,
  ) async {
    GeminiMealService.httpClient = MockClient(
      (request) async => http.Response(_modelReply(), 200),
    );
    final savedRecipes = InMemorySavedRecipesStore();
    await pumpAgent(tester, savedRecipes: savedRecipes);
    await recommend(tester);
    await scrollToActions(tester);
    await tester.tap(find.byKey(const Key('recipeSaveButton')));
    await tester.pumpAndSettle();

    await scrollToActions(tester);
    await tester.tap(find.byKey(const Key('recipeUnsaveButton')));
    await tester.pumpAndSettle();

    expect(savedRecipes.removeCalls, 1);
    expect(savedRecipes.recipes, isEmpty);
    expect(find.text('Removed from saved recipes'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('a failed save keeps the button unsaved and offers Try again', (
    tester,
  ) async {
    GeminiMealService.httpClient = MockClient(
      (request) async => http.Response(_modelReply(), 200),
    );
    final savedRecipes = InMemorySavedRecipesStore()
      ..writeError = Exception('offline');
    await pumpAgent(tester, savedRecipes: savedRecipes);
    await recommend(tester);
    await scrollToActions(tester);

    await tester.tap(find.byKey(const Key('recipeSaveButton')));
    await tester.pumpAndSettle();

    expect(savedRecipes.saveCalls, 1, reason: 'writes are never auto-retried');
    expect(find.text('Try again'), findsOneWidget);
    await scrollToActions(tester);
    expect(find.byKey(const Key('recipeSaveButton')), findsOneWidget);
  });

  testWidgets('the same dish saved twice keeps a single saved recipe', (
    tester,
  ) async {
    GeminiMealService.httpClient = MockClient(
      (request) async => http.Response(_modelReply(), 200),
    );
    final savedRecipes = InMemorySavedRecipesStore();
    await pumpAgent(tester, savedRecipes: savedRecipes);

    for (var round = 0; round < 2; round++) {
      await recommend(tester);
      await scrollToActions(tester);
      final save = find.byKey(const Key('recipeSaveButton'));
      if (save.evaluate().isNotEmpty) {
        await tester.tap(save);
        await tester.pumpAndSettle();
      }
    }

    expect(savedRecipes.recipes, hasLength(1));
    expect(
      savedRecipes.recipes.single.id,
      recipeFingerprint(savedRecipes.recipes.single.recipe),
    );
  });
}

import 'dart:convert';

import 'package:diabetes/design/app_theme.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_preferences_store.dart';
import 'support/in_memory_saved_recipes_store.dart';

String _modelReply() => jsonEncode({
  'candidates': [
    {
      'content': {
        'parts': [
          {
            'text': jsonEncode([
              {
                'dishName': 'Pantry fried rice',
                'imagePrompt': 'a bowl of fried rice',
                'reason': 'Uses pantry basics only.',
                'ingredients': ['Rice', 'Egg'],
                'instructions': ['Fry the rice.', 'Add the egg.'],
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
  var requests = 0;

  setUp(() {
    originalClient = GeminiMealService.httpClient;
    requests = 0;
    GeminiMealService.httpClient = MockClient((request) async {
      requests++;
      return http.Response(_modelReply(), 200);
    });
    AppEnvironment.setGeminiApiKeyForTesting('test-key');
  });

  tearDown(() {
    GeminiMealService.httpClient = originalClient;
    AppEnvironment.setGeminiApiKeyForTesting('');
  });

  Future<int> pumpAgent(
    WidgetTester tester, {
    required bool firstMealGuide,
    List<FoodItem> foodItems = const [],
    void Function()? onDone,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AgentPage(
            foodItems: foodItems,
            userId: 'user-1',
            geminiApiKey: 'test-key',
            diabetesEnabled: false,
            preferencesRepository: FakePreferencesStore(mealQaTipSeen: true),
            savedRecipesStore: InMemorySavedRecipesStore(),
            firstMealGuide: firstMealGuide,
            onFirstMealGuideDone: onDone,
          ),
        ),
      ),
    );
    await tester.pump();
    return requests;
  }

  /// The prompt, chips, and button don't all fit on a small phone with the
  /// coach card on top, and a ListView only builds what's visible.
  Future<void> scrollToButton(WidgetTester tester) async {
    await tester.drag(find.byType(ListView).first, const Offset(0, -240));
    await tester.pump();
  }

  testWidgets('the guide fills in an example prompt and names each control', (
    tester,
  ) async {
    await pumpAgent(tester, firstMealGuide: true);

    expect(find.byKey(const Key('firstMealCoach')), findsOneWidget);
    expect(find.text('Your first meal idea'), findsOneWidget);
    expect(
      find.text(
        'We filled in an example. Change it if you like, pick a meal type, '
        'then tap Recommend a meal.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('agentFoodPrompt')))
          .controller
          ?.text,
      'Something quick and easy',
    );
    await scrollToButton(tester);
    expect(find.byKey(const Key('firstMealSpotlight')), findsOneWidget);
    expect(requests, 0, reason: 'the guide never asks on the user\'s behalf');
  });

  testWidgets('an empty fridge is called out as fine', (tester) async {
    await pumpAgent(tester, firstMealGuide: true);
    expect(
      find.text("Your fridge is empty, so we'll suggest pantry basics."),
      findsOneWidget,
    );
  });

  testWidgets('a stocked fridge drops the empty-fridge note', (tester) async {
    await pumpAgent(
      tester,
      firstMealGuide: true,
      foodItems: const [
        FoodItem(name: 'Rice', amount: '1 cup', foodType: FoodType.grain),
      ],
    );
    expect(
      find.text("Your fridge is empty, so we'll suggest pantry basics."),
      findsNothing,
    );
  });

  testWidgets('the first recipe ends the guide and points at Save recipe', (
    tester,
  ) async {
    var done = 0;
    await pumpAgent(tester, firstMealGuide: true, onDone: () => done++);

    await scrollToButton(tester);
    await tester.tap(find.byKey(const Key('recommendMealButton')));
    await tester.pumpAndSettle();

    expect(find.text('Pantry fried rice'), findsOneWidget);
    expect(requests, 1);
    expect(done, 1);
    await tester.drag(find.byType(ListView).first, const Offset(0, 400));
    await tester.pump();
    expect(find.byKey(const Key('firstMealCoach')), findsNothing);
    expect(find.byKey(const Key('firstMealSpotlight')), findsNothing);
    expect(
      find.text('Nice! Tap Save recipe to keep it on Home.'),
      findsOneWidget,
    );

    // A second recommendation doesn't re-run the guide.
    await tester.tap(find.byKey(const Key('firstMealDoneTipDismiss')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('recommendMealButton')));
    await tester.pumpAndSettle();
    expect(done, 1);
    expect(find.byKey(const Key('firstMealCoach')), findsNothing);
  });

  testWidgets('Skip tour hides the coach and marks the guide done', (
    tester,
  ) async {
    var done = 0;
    await pumpAgent(tester, firstMealGuide: true, onDone: () => done++);

    await tester.tap(find.byKey(const Key('firstMealSkipTour')));
    await tester.pump();

    expect(find.byKey(const Key('firstMealCoach')), findsNothing);
    expect(done, 1);
    // Skipping leaves the prompt alone so the user can still ask.
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('agentFoodPrompt')))
          .controller
          ?.text,
      'Something quick and easy',
    );
    expect(find.byKey(const Key('recommendMealButton')), findsOneWidget);
  });

  testWidgets('a returning user gets no coach and an empty prompt', (
    tester,
  ) async {
    await pumpAgent(tester, firstMealGuide: false);

    expect(find.byKey(const Key('firstMealCoach')), findsNothing);
    expect(find.byKey(const Key('firstMealSpotlight')), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('agentFoodPrompt')))
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('the guide holds the outline still under reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: AgentPage(
              foodItems: const [],
              userId: 'user-1',
              geminiApiKey: 'test-key',
              diabetesEnabled: false,
              preferencesRepository: FakePreferencesStore(mealQaTipSeen: true),
              savedRecipesStore: InMemorySavedRecipesStore(),
              firstMealGuide: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await scrollToButton(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('firstMealSpotlight')), findsOneWidget);
    // No pending frames means nothing is animating.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

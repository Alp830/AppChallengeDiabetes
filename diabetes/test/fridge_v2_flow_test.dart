import 'dart:async';
import 'dart:convert';

import 'package:diabetes/ai/ai_retry.dart';
import 'package:diabetes/design/app_theme.dart';
import 'package:diabetes/exercise/data/today_todo_repository.dart';
import 'package:diabetes/home/mvp_home_page.dart';
import 'package:diabetes/main.dart';
import 'package:diabetes/meals/saved/saved_recipe.dart';
import 'package:diabetes/meals/saved/saved_recipes_page.dart';
import 'package:diabetes/meals/services/meal_qa_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_preferences_store.dart';
import 'support/in_memory_saved_recipes_store.dart';

/// End-to-end paths that cross the fridge, retry, and onboarding work: each
/// test here goes through a screen the user actually taps, not a service.

/// One recommendation in Gemini's `generateContent` envelope.
http.Response _recipeReply({String dishName = 'Pantry fried rice'}) =>
    http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'text': jsonEncode([
                    {
                      'dishName': dishName,
                      'imagePrompt': 'a bowl of $dishName',
                      'reason': 'Uses pantry basics only.',
                      'ingredients': ['1 lemon', '200g chicken'],
                      'instructions': ['Cook the rice.', 'Add the egg.'],
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

/// Plain prose in the same envelope, for the Q&A round trips.
http.Response _geminiText(String text) => http.Response(
  jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': text},
          ],
        },
      },
    ],
  }),
  200,
);

http.Response _busy() => http.Response('busy', 503);

/// Only `suggestQuestions` asks for a `responseSchema`, so the chip request
/// can be told apart from the answer request.
bool _isChipsRequest(http.Request request) =>
    request.body.contains('responseSchema');

/// A phone-sized surface: these screens lay out a column of cards and the
/// default 800x600 test window hides the wrong half of them.
void _usePhoneView(WidgetTester tester, {double height = 780}) {
  tester.view.physicalSize = Size(360, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('the first guided recipe survives a hiccup', () {
    late http.Client originalClient;
    late AiRetryPolicy originalPolicy;
    late List<Completer<http.Response>> pending;
    late List<String> bodies;

    setUp(() {
      originalClient = GeminiMealService.httpClient;
      originalPolicy = AgentPage.retryPolicy;
      // Zero spacing: ai_retry_test covers the 2 s wait, and sitting through
      // four of them here would add 8 s per test.
      AgentPage.retryPolicy = const AiRetryPolicy(delay: Duration.zero);
      AppEnvironment.setGeminiApiKeyForTesting('test-key');
      pending = [];
      bodies = [];
      // Deferred replies: the retry loop only moves when the test says so.
      GeminiMealService.httpClient = MockClient((request) {
        bodies.add(request.body);
        final completer = Completer<http.Response>();
        pending.add(completer);
        return completer.future;
      });
    });

    tearDown(() {
      GeminiMealService.httpClient = originalClient;
      AgentPage.retryPolicy = originalPolicy;
      AppEnvironment.setGeminiApiKeyForTesting('');
    });

    Future<void> pumpGuidedAgent(
      WidgetTester tester, {
      required VoidCallback onDone,
    }) async {
      _usePhoneView(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AgentPage(
              foodItems: const [],
              userId: 'user-1',
              geminiApiKey: 'test-key',
              diabetesEnabled: false,
              preferencesRepository: FakePreferencesStore(mealQaTipSeen: true),
              savedRecipesStore: InMemorySavedRecipesStore(),
              firstMealGuide: true,
              onFirstMealGuideDone: onDone,
            ),
          ),
        ),
      );
      await tester.pump();
      // The coach card pushes the button off a small phone, and a ListView
      // only builds what is visible.
      await tester.drag(find.byType(ListView).first, const Offset(0, -240));
      await tester.pump();
    }

    /// Answers the outstanding attempt, then lets the loop reach the next.
    Future<void> settleAttempt(
      WidgetTester tester,
      http.Response response,
    ) async {
      pending.removeAt(0).complete(response);
      await tester.pump();
      await tester.pump(Duration.zero);
    }

    testWidgets('one 503, then the recipe, and the guide hands over the '
        'save tip exactly once', (tester) async {
      var done = 0;
      await pumpGuidedAgent(tester, onDone: () => done++);

      await tester.tap(find.byKey(const Key('recommendMealButton')));
      await tester.pump();
      expect(pending, hasLength(1));
      expect(find.textContaining('Retrying'), findsNothing);

      await settleAttempt(tester, _busy());
      expect(find.text('AI request failed. Retrying 2/5'), findsOneWidget);
      expect(find.byKey(const Key('firstMealCoach')), findsOneWidget);
      expect(done, 0, reason: 'a retry is not a finished guide');

      await settleAttempt(tester, _recipeReply());
      await tester.pumpAndSettle();

      expect(bodies, hasLength(2));
      expect(bodies.toSet(), hasLength(1), reason: 'same request retried');
      expect(find.text('Pantry fried rice'), findsOneWidget);
      expect(find.byKey(const Key('aiRetryStatus')), findsNothing);
      expect(find.textContaining('Retrying'), findsNothing);
      expect(done, 1);

      // Back to the top: the coach is gone and the save tip took its place.
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pump();
      expect(find.byKey(const Key('firstMealCoach')), findsNothing);
      expect(find.byKey(const Key('firstMealSpotlight')), findsNothing);
      expect(find.byKey(const Key('firstMealDoneTip')), findsOneWidget);
      expect(
        find.text('Nice! Tap Save recipe to keep it on Home.'),
        findsOneWidget,
      );
    });

    testWidgets('a guided run that fails every try leaves the guide pending', (
      tester,
    ) async {
      var done = 0;
      await pumpGuidedAgent(tester, onDone: () => done++);

      await tester.tap(find.byKey(const Key('recommendMealButton')));
      await tester.pump();
      for (var attempt = 0; attempt < 5; attempt++) {
        await settleAttempt(tester, _busy());
      }
      // Not pumpAndSettle: the coach's spotlight outline pulses for as long as
      // the guide is pending, so there is never a settled frame.
      await tester.pump();

      expect(bodies, hasLength(5));
      expect(
        find.text(
          "Couldn't get a meal idea after a few tries. "
          'Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(done, 0, reason: 'the user never saw a recipe');
      expect(find.byKey(const Key('firstMealDoneTip')), findsNothing);

      // The coach is still there to try again with.
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pump();
      expect(find.byKey(const Key('firstMealCoach')), findsOneWidget);
    });
  });

  group('a saved recipe answers questions through the same retry loop', () {
    late http.Client originalGeminiClient;
    late http.Client originalQaClient;
    late List<Completer<http.Response>> pendingAnswers;
    var httpCalls = 0;
    var chipCalls = 0;

    setUp(() {
      originalGeminiClient = GeminiMealService.httpClient;
      originalQaClient = MealQaService.httpClient;
      httpCalls = 0;
      chipCalls = 0;
      pendingAnswers = [];
      final client = MockClient((request) {
        httpCalls++;
        // Chips are a nicety and never retried; answering them right away
        // keeps the deferred queue to the answer round trips.
        if (_isChipsRequest(request)) {
          chipCalls++;
          return Future.value(_geminiText('[]'));
        }
        final completer = Completer<http.Response>();
        pendingAnswers.add(completer);
        return completer.future;
      });
      GeminiMealService.httpClient = client;
      MealQaService.httpClient = client;
      AppEnvironment.setGeminiApiKeyForTesting('test-key');
    });

    tearDown(() {
      GeminiMealService.httpClient = originalGeminiClient;
      MealQaService.httpClient = originalQaClient;
      AppEnvironment.setGeminiApiKeyForTesting('');
    });

    testWidgets('opening it asks nothing, and its Q&A counts the tries', (
      tester,
    ) async {
      _usePhoneView(tester);
      final recipe = MealRecommendation(
        dishName: 'Lemon chicken bowl',
        imagePrompt: 'a lemon chicken bowl',
        reason: 'Quick and uses pantry basics.',
        ingredients: const ['1 lemon', '200g chicken'],
        instructions: const ['Cook the rice.', 'Grill the chicken.'],
      );
      final store = InMemorySavedRecipesStore(
        initial: [
          SavedRecipe(
            id: recipeFingerprint(recipe),
            recipe: recipe,
            savedAt: DateTime(2026, 9, 28, 10),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SavedRecipesPage(
            userId: 'user-1',
            store: store,
            geminiApiKey: 'test-key',
            diabetesEnabled: false,
            preferencesRepository: FakePreferencesStore(mealQaTipSeen: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(httpCalls, 0, reason: 'the list reads stored data');

      await tester.tap(find.byKey(const Key('savedRecipe_0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('savedRecipeDetail')), findsOneWidget);
      expect(httpCalls, 0, reason: 'a saved recipe opens from stored data');

      // Ask about an ingredient, the way the Meals tab does.
      await tester.ensureVisible(find.byKey(const Key('mealQaIngredient_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mealQaIngredient_0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mealQaInput')), findsOneWidget);
      expect(chipCalls, 1);

      await tester.enterText(
        find.byKey(const Key('mealQaInput')),
        'Can I swap the lemon?',
      );
      await tester.tap(find.byKey(const Key('mealQaSend')));
      await tester.pump();
      expect(pendingAnswers, hasLength(1));
      expect(find.textContaining('Retrying'), findsNothing);

      pendingAnswers.removeAt(0).complete(_busy());
      await tester.pump();
      // The saved-recipe sheet keeps the production 2 s spacing.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('AI request failed. Retrying 2/5'), findsOneWidget);
      expect(pendingAnswers, hasLength(1), reason: 'attempt 2 is in flight');

      pendingAnswers.removeAt(0).complete(_geminiText('Lime works too.'));
      await tester.pumpAndSettle();

      expect(find.text('Lime works too.'), findsOneWidget);
      expect(find.textContaining('Retrying'), findsNothing);
      expect(find.byKey(const Key('mealQaError')), findsNothing);
      expect(httpCalls, 3, reason: 'one chip request and two answer attempts');
    });
  });

  group('leaving Meals mid-retry', () {
    late http.Client originalClient;
    late AiRetryPolicy originalPolicy;
    late List<Completer<http.Response>> pending;
    late List<String> bodies;

    setUp(() {
      originalClient = GeminiMealService.httpClient;
      originalPolicy = AgentPage.retryPolicy;
      // Short but real spacing, so "no calls after leaving" is checked across
      // several delays instead of across nothing.
      AgentPage.retryPolicy = const AiRetryPolicy(
        delay: Duration(milliseconds: 200),
      );
      AppEnvironment.setGeminiApiKeyForTesting('test-key');
      pending = [];
      bodies = [];
      GeminiMealService.httpClient = MockClient((request) {
        bodies.add(request.body);
        final completer = Completer<http.Response>();
        pending.add(completer);
        return completer.future;
      });
    });

    tearDown(() {
      GeminiMealService.httpClient = originalClient;
      AgentPage.retryPolicy = originalPolicy;
      AppEnvironment.setGeminiApiKeyForTesting('');
    });

    Future<GlobalKey<AgentPageState>> pumpAgent(WidgetTester tester) async {
      _usePhoneView(tester, height: 900);
      final agentKey = GlobalKey<AgentPageState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AgentPage(
              key: agentKey,
              foodItems: const [],
              userId: 'user-1',
              geminiApiKey: 'test-key',
              diabetesEnabled: false,
              preferencesRepository: FakePreferencesStore(mealQaTipSeen: true),
              savedRecipesStore: InMemorySavedRecipesStore(),
            ),
          ),
        ),
      );
      await tester.pump();
      return agentKey;
    }

    /// Fails attempts until the status line reaches [attempt] of 5. Each
    /// failure is followed by the retry delay, so the count is the app's.
    Future<void> failUntilAttempt(WidgetTester tester, int attempt) async {
      await tester.tap(find.byKey(const Key('recommendMealButton')));
      await tester.pump();
      for (var number = 2; number <= attempt; number++) {
        pending.removeAt(0).complete(_busy());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(
        find.text('AI request failed. Retrying $attempt/5'),
        findsOneWidget,
      );
      expect(bodies, hasLength(attempt));
    }

    /// Runs the guard the shell runs on a tab switch, then taps [answerKey].
    Future<bool> confirmLeave(
      WidgetTester tester,
      GlobalKey<AgentPageState> agentKey,
      String answerKey,
    ) async {
      final decision = agentKey.currentState!.confirmLeave();
      // Fixed pumps rather than pumpAndSettle: the retry status spinner never
      // stops, so nothing settles while a retry is on screen. The attempt in
      // flight is held by the test, so no retry slips through these frames.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Stop waiting for your meal idea?'), findsOneWidget);
      await tester.tap(find.byKey(Key(answerKey)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return decision;
    }

    testWidgets('Leave stops the loop: no more calls, nothing loading', (
      tester,
    ) async {
      final agentKey = await pumpAgent(tester);
      await failUntilAttempt(tester, 3);

      expect(await confirmLeave(tester, agentKey, 'agentLeave'), isTrue);
      expect(agentKey.currentState!.isLoadingRecommendation, isFalse);

      // The attempt that was in flight comes back after the user gave up.
      pending.removeAt(0).complete(_busy());
      for (var tick = 0; tick < 4; tick++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(bodies, hasLength(3), reason: 'leaving starts nothing new');
      expect(find.textContaining('Retrying'), findsNothing);
      expect(find.byKey(const Key('loadErrorRetry')), findsNothing);
      expect(agentKey.currentState!.isLoadingRecommendation, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Keep waiting leaves the loop running', (tester) async {
      final agentKey = await pumpAgent(tester);
      await failUntilAttempt(tester, 2);

      expect(await confirmLeave(tester, agentKey, 'agentKeepWaiting'), isFalse);
      expect(agentKey.currentState!.isLoadingRecommendation, isTrue);

      pending.removeAt(0).complete(_busy());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('AI request failed. Retrying 3/5'), findsOneWidget);
      expect(bodies, hasLength(3), reason: 'the loop kept going');

      // And the answer still lands for the user who waited.
      pending.removeAt(0).complete(_recipeReply());
      await tester.pumpAndSettle();
      expect(find.byType(MealRecommendationCard), findsOneWidget);
      expect(find.textContaining('Retrying'), findsNothing);
      await tester.dragUntilVisible(
        find.text('Pantry fried rice'),
        find.byType(ListView).first,
        const Offset(0, -200),
      );
      expect(find.text('Pantry fried rice'), findsOneWidget);
    });
  });

  group('saving from Meals shows up on Home', () {
    late http.Client originalClient;

    setUp(() {
      originalClient = GeminiMealService.httpClient;
      GeminiMealService.httpClient = MockClient(
        (request) async => _recipeReply(),
      );
      AppEnvironment.setGeminiApiKeyForTesting('test-key');
    });

    tearDown(() {
      GeminiMealService.httpClient = originalClient;
      AppEnvironment.setGeminiApiKeyForTesting('');
    });

    testWidgets('Save recipe writes the store Home reads from', (tester) async {
      _usePhoneView(tester);
      final store = InMemorySavedRecipesStore();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AgentPage(
              foodItems: const [],
              userId: 'user-1',
              geminiApiKey: 'test-key',
              diabetesEnabled: false,
              preferencesRepository: FakePreferencesStore(mealQaTipSeen: true),
              savedRecipesStore: store,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('recommendMealButton')));
      await tester.pumpAndSettle();
      expect(find.text('Pantry fried rice'), findsOneWidget);

      // The save button sits below the recipe's steps.
      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await tester.pump();
      await tester.tap(find.byKey(const Key('recipeSaveButton')));
      await tester.pumpAndSettle();

      expect(store.recipes.single.recipe.dishName, 'Pantry fried rice');
      expect(
        find.text('Saved. Find it on Home under Saved recipes.'),
        findsOneWidget,
      );

      // Home, reading the same store the user just wrote to.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MvpHomePage(
              userId: 'user-1',
              now: DateTime(2026, 9, 28),
              todoStateStream: Stream.value(
                const TodayTodoState(isInitialized: true, items: []),
              ),
              onSaveTodos: (_) async {},
              onOpenFridge: () {},
              fridgeItemCount: 0,
              savedRecipesStore: store,
              onOpenSavedRecipes: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('homeSavedRecipes')), findsOneWidget);
      expect(find.text('Saved recipes'), findsOneWidget);
      expect(
        find.text('1 saved · Pantry fried rice'),
        findsOneWidget,
        reason: 'the card names what was just saved',
      );
    });
  });
}

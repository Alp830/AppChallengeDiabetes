import 'dart:async';
import 'dart:convert';

import 'package:diabetes/ai/ai_retry.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A recommendation payload in Gemini's `generateContent` envelope.
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
  late List<Completer<http.Response>> pending;
  late List<String> bodies;

  setUp(() {
    originalClient = GeminiMealService.httpClient;
    originalPolicy = AgentPage.retryPolicy;
    // Zero spacing: the 2 s wait is covered by ai_retry_test, and waiting for
    // it here would make every retry test 8 s long.
    AgentPage.retryPolicy = const AiRetryPolicy(delay: Duration.zero);
    GeminiMealService.debugApiKey = 'test-token';
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
    GeminiMealService.debugApiKey = null;
    AgentPage.retryPolicy = originalPolicy;
  });

  Future<void> pumpAgent(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AgentPage(foodItems: [])),
      ),
    );
  }

  Future<void> requestMeal(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('recommendMealButton')));
    await tester.pump();
  }

  /// Answers the outstanding request, then lets the loop reach its next one.
  Future<void> settleAttempt(
    WidgetTester tester,
    http.Response response,
  ) async {
    pending.removeAt(0).complete(response);
    await tester.pump();
    await tester.pump(Duration.zero);
  }

  testWidgets('two hiccups then a recipe, counting the tries out loud', (
    tester,
  ) async {
    await pumpAgent(tester);
    await requestMeal(tester);

    expect(pending, hasLength(1));
    expect(find.byKey(const Key('aiRetryStatus')), findsNothing);

    await settleAttempt(tester, http.Response('busy', 503));
    expect(find.text('AI request failed. Retrying 2/5'), findsOneWidget);

    await settleAttempt(tester, http.Response('busy', 503));
    expect(find.text('AI request failed. Retrying 3/5'), findsOneWidget);

    await settleAttempt(tester, _recipeResponse());
    await tester.pumpAndSettle();

    expect(bodies, hasLength(3));
    expect(find.text('Lemon chicken bowl'), findsOneWidget);
    expect(find.byKey(const Key('aiRetryStatus')), findsNothing);
    expect(find.textContaining('Retrying'), findsNothing);
  });

  testWidgets('every attempt sends the identical request', (tester) async {
    await pumpAgent(tester);
    await tester.enterText(
      find.byKey(const Key('agentFoodPrompt')),
      'Something with eggs',
    );
    await requestMeal(tester);

    for (var i = 0; i < 3; i++) {
      await settleAttempt(tester, http.Response('busy', 503));
    }
    await settleAttempt(tester, _recipeResponse());
    await tester.pumpAndSettle();

    expect(bodies, hasLength(4));
    expect(bodies.toSet(), hasLength(1), reason: 'same prompt every time');
    expect(bodies.first, contains('Something with eggs'));
  });

  testWidgets('five failures end in a friendly error with Try again', (
    tester,
  ) async {
    await pumpAgent(tester);
    await requestMeal(tester);

    for (var i = 0; i < 5; i++) {
      await settleAttempt(tester, http.Response('busy', 503));
    }
    await tester.pumpAndSettle();

    expect(bodies, hasLength(5));
    expect(
      find.text(
        "Couldn't get a meal idea after a few tries. "
        'Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('loadErrorRetry')), findsOneWidget);
    expect(find.textContaining('Retrying'), findsNothing);

    // Try again starts a fresh set: a 6th call, and no counter until it fails.
    await tester.tap(find.byKey(const Key('loadErrorRetry')));
    await tester.pump();
    expect(bodies, hasLength(6));
    expect(find.textContaining('Retrying'), findsNothing);

    await settleAttempt(tester, http.Response('busy', 503));
    expect(find.text('AI request failed. Retrying 2/5'), findsOneWidget);
    expect(bodies, hasLength(7));
  });

  testWidgets('a rejected request is not sent twice', (tester) async {
    await pumpAgent(tester);
    await requestMeal(tester);

    await settleAttempt(tester, http.Response('bad request', 400));
    await tester.pumpAndSettle();

    expect(bodies, hasLength(1));
    expect(
      find.text("That request didn't work. Try changing it and try again."),
      findsOneWidget,
    );
  });

  testWidgets('leaving the screen mid-retry stops the attempts', (
    tester,
  ) async {
    await pumpAgent(tester);
    await requestMeal(tester);
    await settleAttempt(tester, http.Response('busy', 503));
    expect(find.text('AI request failed. Retrying 2/5'), findsOneWidget);
    expect(bodies, hasLength(2));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('elsewhere'))),
    );
    pending.removeAt(0).complete(http.Response('busy', 503));
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    expect(bodies, hasLength(2), reason: 'no attempt survives dispose');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelRecommendation drops a late result', (tester) async {
    final key = GlobalKey<AgentPageState>();
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentPage(key: key, foodItems: const []),
        ),
      ),
    );
    await requestMeal(tester);
    expect(key.currentState!.isLoadingRecommendation, isTrue);

    key.currentState!.cancelRecommendation();
    await tester.pump();
    expect(key.currentState!.isLoadingRecommendation, isFalse);

    pending.removeAt(0).complete(_recipeResponse());
    await tester.pumpAndSettle();

    expect(find.text('Lemon chicken bowl'), findsNothing);
    expect(find.textContaining('Retrying'), findsNothing);
    expect(bodies, hasLength(1));
  });
}

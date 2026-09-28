import 'dart:async';
import 'dart:convert';

import 'package:diabetes/ai/ai_retry.dart';
import 'package:diabetes/main.dart';
import 'package:diabetes/meals/models/meal_qa_models.dart';
import 'package:diabetes/meals/screens/meal_qa_sheet.dart';
import 'package:diabetes/meals/services/meal_qa_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Wraps text in Gemini's `generateContent` response envelope.
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

const _meal = MealQaContext(
  dishName: 'Lemon Chicken and Quinoa',
  reason: 'High fiber keeps the rise gradual.',
  ingredients: ['1 cup quinoa', '2 chicken thighs'],
  instructions: ['Rinse the quinoa.', 'Sear until golden, then deglaze.'],
  glucoseNote: 'Pair with a short walk.',
  eveningScore: 4,
  usedFridgeItems: ['quinoa'],
  estimatedCostPerServing: r'$2-3/serving',
);

const _tip = 'Tip: tap any ingredient or step to ask about it directly.';

/// The suggestQuestions call is the only one that asks for a responseSchema,
/// so tests can tell the two round trips apart.
bool _isChipsRequest(http.Request request) =>
    request.body.contains('responseSchema');

const _stepScope = MealQuestionScope(
  kind: MealQuestionScopeKind.step,
  quote: 'Sear until golden, then deglaze.',
  ordinal: 2,
);

MealRecommendation _recommendation({
  List<String> suggestedQuestions = const [],
}) => MealRecommendation(
  dishName: 'Lemon Chicken and Quinoa',
  imagePrompt: '',
  reason: 'High fiber keeps the rise gradual.',
  ingredients: const ['1 cup quinoa', '2 chicken thighs'],
  instructions: const ['Rinse the quinoa.', 'Sear until golden.'],
  glucoseNote: 'Pair with a short walk.',
  suggestedQuestions: suggestedQuestions,
);

void main() {
  group('MealQaService.answer', () {
    test('posts to the flash endpoint with the api key header', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _geminiText('Deglazing lifts the browned bits into a sauce.');
      });

      final reply = await MealQaService(apiKey: 'test-token', client: client)
          .answer(
            meal: _meal,
            scope: _stepScope,
            history: const [],
            question: 'What does deglaze mean?',
          );

      expect(reply, 'Deglazing lifts the browned bits into a sauce.');
      expect(captured.url.toString(), MealQaService.endpoint);
      expect(captured.headers['x-goog-api-key'], 'test-token');
      expect(captured.body, contains('What does deglaze mean?'));
    });

    test('never sends glucose readings, identity, or overnight data', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _geminiText('Sure.');
      });

      await MealQaService(apiKey: 'test-token', client: client).answer(
        meal: _meal,
        scope: const MealQuestionScope.meal(),
        history: const [],
        question: 'Can I make this ahead?',
      );

      final body = captured.body.toLowerCase();
      expect(body, isNot(contains('userid')));
      expect(body, isNot(contains('mg/dl')));
      expect(body, isNot(contains('mmol')));
      expect(body, isNot(contains('overnight')));
      expect(body, isNot(contains('timeinrange')));
      // The dish itself must still be there, or the agent has no context.
      expect(body, contains('lemon chicken'));
    });

    test(
      'surfaces a non-200 as MealQaException including status and body',
      () async {
        final client = MockClient(
          (request) async => http.Response('quota exhausted', 429),
        );

        await expectLater(
          MealQaService(apiKey: 'test-token', client: client).answer(
            meal: _meal,
            scope: _stepScope,
            history: const [],
            question: 'Why?',
          ),
          throwsA(
            isA<MealQaException>()
                .having((e) => e.message, 'message', contains('429'))
                .having(
                  (e) => e.message,
                  'message',
                  contains('quota exhausted'),
                ),
          ),
        );
      },
    );

    test('malformed payloads throw MealQaException, not TypeError', () async {
      final payloads = <String>[
        jsonEncode({'candidates': <dynamic>[]}),
        jsonEncode({
          'candidates': [
            {'content': <String, dynamic>{}},
          ],
        }),
        jsonEncode({
          'candidates': [
            {
              'content': {'parts': <dynamic>[]},
            },
          ],
        }),
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [<String, dynamic>{}],
              },
            },
          ],
        }),
        'not json at all',
      ];

      for (final payload in payloads) {
        final client = MockClient(
          (request) async => http.Response(payload, 200),
        );
        await expectLater(
          MealQaService(apiKey: 'test-token', client: client).answer(
            meal: _meal,
            scope: _stepScope,
            history: const [],
            question: 'Why?',
          ),
          throwsA(isA<MealQaException>()),
          reason: 'payload: $payload',
        );
      }
    });

    test('ignores thinking parts and returns only the answer', () async {
      // gemini-3-flash-preview emits a reasoning part flagged `thought` BEFORE
      // the answer. Taking parts.first rendered the model's deliberation to
      // the user.
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'thought': true, 'text': 'No background/restatement?*'},
                    {'text': 'You will see the water run clear after 30 '},
                    {'text': 'seconds of rinsing.'},
                  ],
                },
              },
            ],
          }),
          200,
        ),
      );

      final reply = await MealQaService(apiKey: 'test-token', client: client)
          .answer(
            meal: _meal,
            scope: _stepScope,
            history: const [],
            question: 'How do I know when the water runs clear?',
          );

      expect(
        reply,
        'You will see the water run clear after 30 seconds of rinsing.',
      );
      expect(reply, isNot(contains('No background')));
    });

    test(
      'a thinking-only response reports truncation instead of empty',
      () async {
        final client = MockClient(
          (request) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'MAX_TOKENS',
                  'content': {
                    'parts': [
                      {'thought': true, 'text': 'thinking...'},
                    ],
                  },
                },
              ],
            }),
            200,
          ),
        );

        await expectLater(
          MealQaService(apiKey: 'test-token', client: client).answer(
            meal: _meal,
            scope: _stepScope,
            history: const [],
            question: 'Why?',
          ),
          throwsA(
            isA<MealQaException>().having(
              (e) => e.message,
              'message',
              contains('ran out of room'),
            ),
          ),
        );
      },
    );

    test(
      'sends the rules as systemInstruction and the recipe as the user turn',
      () async {
        late http.Request captured;
        final client = MockClient((request) async {
          captured = request;
          return _geminiText('Sure.');
        });

        await MealQaService(apiKey: 'test-token', client: client).answer(
          meal: _meal,
          scope: _stepScope,
          history: const [],
          question: 'Why?',
        );

        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        final system =
            ((body['systemInstruction'] as Map)['parts'] as List).first as Map;
        expect(system['text'], contains('NO markdown'));

        final userTurn = (body['contents'] as List).first as Map;
        final userText = ((userTurn['parts'] as List).first as Map)['text'];
        expect(userText, contains('1 cup quinoa'));
        expect(userText, isNot(contains('NO markdown')));

        // Thinking tokens share the output budget, so it must be generous.
        final config = body['generationConfig'] as Map;
        expect(config['maxOutputTokens'], greaterThanOrEqualTo(2048));
        expect((config['thinkingConfig'] as Map)['thinkingLevel'], 'low');
      },
    );

    test('missing api key throws before any network call', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return _geminiText('nope');
      });

      await expectLater(
        MealQaService(apiKey: '', client: client).answer(
          meal: _meal,
          scope: _stepScope,
          history: const [],
          question: 'Why?',
        ),
        throwsA(isA<MealQaException>()),
      );
      expect(called, isFalse);
    });

    test('carries a retry verdict the shared rule understands', () async {
      Future<MealQaException> failWith(http.Response response) async {
        try {
          await MealQaService(
            apiKey: 'test-token',
            client: MockClient((_) async => response),
          ).answer(
            meal: _meal,
            scope: _stepScope,
            history: const [],
            question: 'Why?',
          );
        } on MealQaException catch (error) {
          return error;
        }
        fail('expected a MealQaException');
      }

      final busy = await failWith(http.Response('busy', 503));
      expect(busy.statusCode, 503);
      expect(isRetryableAiError(busy), isTrue);

      final forbidden = await failWith(http.Response('nope', 403));
      expect(forbidden.statusCode, 403);
      expect(isRetryableAiError(forbidden), isFalse);

      final empty = await failWith(http.Response('{"candidates": []}', 200));
      expect(isRetryableAiError(empty), isTrue, reason: 'empty model reply');

      MealQaException? missingKey;
      try {
        await MealQaService(apiKey: '').answer(
          meal: _meal,
          scope: _stepScope,
          history: const [],
          question: 'Why?',
        );
      } on MealQaException catch (error) {
        missingKey = error;
      }
      expect(isRetryableAiError(missingKey!), isFalse);
    });
  });

  group('MealQaService.suggestQuestions', () {
    test('parses a fenced JSON array and caps at three', () async {
      final client = MockClient(
        (request) async => _geminiText(
          '```json\n["What does deglaze mean?","Can I skip it?","How hot?","Extra"]\n```',
        ),
      );

      final chips = await MealQaService(
        apiKey: 'test-token',
        client: client,
      ).suggestQuestions(_meal, _stepScope);

      expect(chips, ['What does deglaze mean?', 'Can I skip it?', 'How hot?']);
    });

    test('degrades to an empty row instead of throwing', () async {
      final client = MockClient(
        (request) async => http.Response('server exploded', 500),
      );

      final chips = await MealQaService(
        apiKey: 'test-token',
        client: client,
      ).suggestQuestions(_meal, _stepScope);

      expect(chips, isEmpty);
    });
  });

  group('buildAnswerPrompt', () {
    test('carries the tapped line, the dish, and the safety rules', () {
      final prompt = MealQaService.buildAnswerPrompt(
        meal: _meal,
        scope: _stepScope,
        history: const [],
        question: 'What does deglaze mean?',
      );

      // The user turn carries the full recipe and what was tapped...
      expect(prompt, contains('Sear until golden, then deglaze.'));
      expect(prompt, contains('step 2'));
      expect(prompt, contains('Lemon Chicken and Quinoa'));
      expect(prompt, contains('1 cup quinoa'));
      expect(prompt, contains('Rinse the quinoa.'));
      // ...and the rules live in the system instruction, not the user turn,
      // so the model follows them instead of reasoning about them out loud.
      expect(prompt, isNot(contains('NO markdown')));
    });

    test('the system instruction carries the rules and guardrails', () {
      const rules = MealQaService.answerSystemInstruction;

      expect(rules, contains('NO markdown'));
      // Specificity guardrails — vague answers were the first thing to go wrong.
      expect(rules, contains('EXACT QUESTION ASKED'));
      expect(rules, contains('SEE'));
      expect(rules, contains('generic dictionary'));
      expect(rules, contains('insulin or medication dosing'));
      expect(rules, contains('care team'));
      // It must never claim it lacks the recipe — it always has it.
      expect(rules, contains('Never say you lack context'));
      expect(rules, contains('describe your own reasoning'));
    });

    test('replays prior turns in order', () {
      final prompt = MealQaService.buildAnswerPrompt(
        meal: _meal,
        scope: _stepScope,
        history: const [
          MealQaTurn.user('What does deglaze mean?'),
          MealQaTurn.agent('It lifts the browned bits into a sauce.'),
        ],
        question: 'Can I use water?',
      );

      final first = prompt.indexOf('What does deglaze mean?');
      final second = prompt.indexOf('It lifts the browned bits');
      expect(first, greaterThan(-1));
      expect(second, greaterThan(first));
    });
  });

  group('MealRecommendation.suggestedQuestions', () {
    test('parses, trims, drops blanks and non-strings, and caps at three', () {
      final recommendation = MealRecommendation.fromJson(const {
        'dishName': 'Dish',
        'reason': 'Because',
        'ingredients': ['a'],
        'instructions': ['b'],
        'suggestedQuestions': ['  One?  ', '', 42, 'Two?', 'Three?', 'Four?'],
      });

      expect(recommendation.suggestedQuestions, ['One?', 'Two?', 'Three?']);
    });

    test('defaults to empty when the model omits the field', () {
      final recommendation = MealRecommendation.fromJson(const {
        'dishName': 'Dish',
        'reason': 'Because',
        'ingredients': ['a'],
        'instructions': ['b'],
      });

      expect(recommendation.suggestedQuestions, isEmpty);
    });

    test('survives copyWith, which the image pipeline runs every time', () {
      final withImage = _recommendation(
        suggestedQuestions: const ['One?'],
      ).copyWith(imageUrl: 'https://example.test/dish.jpg');

      expect(withImage.suggestedQuestions, ['One?']);
    });

    test('the recommendation prompt asks for the field', () {
      final prompt = GeminiMealService.buildPromptForTesting(
        const AgentRequest(
          useFridgeItems: false,
          hasBudget: false,
          budget: '',
          hasTimeShortage: false,
          timeAvailable: '',
          foodPreferences: '',
          mealType: MealType.dinner,
          cookingExperience: CookingExperience.beginner,
          recommendationCount: 1,
          fridgeItems: [],
          feedbackHistory: [],
        ),
      );

      expect(prompt, contains('suggestedQuestions'));
    });
  });

  group('MealRecommendationCard tap targets', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required MealRecommendation recommendation,
      void Function(MealQuestionScope scope, {String? initialQuestion})? onAsk,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MealRecommendationCard(
              recommendation: recommendation,
              diabetesEnabled: true,
              onAsk: onAsk,
            ),
          ),
        ),
      ),
    );

    testWidgets('tapping a step asks about that exact step', (tester) async {
      MealQuestionScope? scope;
      await pumpCard(
        tester,
        recommendation: _recommendation(),
        onAsk: (value, {String? initialQuestion}) => scope = value,
      );

      await tester.ensureVisible(find.byKey(const Key('mealQaStep_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mealQaStep_1')));
      await tester.pump();

      expect(scope?.kind, MealQuestionScopeKind.step);
      expect(scope?.ordinal, 2);
      expect(scope?.quote, 'Sear until golden.');
      expect(scope?.label, 'step 2');
    });

    testWidgets('tapping an ingredient asks about that ingredient', (
      tester,
    ) async {
      MealQuestionScope? scope;
      await pumpCard(
        tester,
        recommendation: _recommendation(),
        onAsk: (value, {String? initialQuestion}) => scope = value,
      );

      await tester.tap(find.byKey(const Key('mealQaIngredient_0')));
      await tester.pump();

      expect(scope?.kind, MealQuestionScopeKind.ingredient);
      expect(scope?.quote, '1 cup quinoa');
    });

    testWidgets('a chip submits its own text immediately', (tester) async {
      MealQuestionScope? scope;
      String? opening;
      await pumpCard(
        tester,
        recommendation: _recommendation(
          suggestedQuestions: const ['Why is this good for my blood sugar?'],
        ),
        onAsk: (value, {String? initialQuestion}) {
          scope = value;
          opening = initialQuestion;
        },
      );

      await tester.ensureVisible(find.byKey(const Key('mealQaChip_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mealQaChip_0')));
      await tester.pump();

      expect(scope?.kind, MealQuestionScopeKind.meal);
      expect(opening, 'Why is this good for my blood sugar?');
    });

    testWidgets('lays out without overflow on a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpCard(
        tester,
        recommendation: const MealRecommendation(
          dishName: 'Lemon Chicken and Quinoa',
          imagePrompt: '',
          reason: 'High fiber and lean protein keep the rise gradual.',
          ingredients: ['1 cup quinoa', '2 chicken thighs'],
          instructions: ['Rinse the quinoa until the water runs clear.'],
          glucoseNote: 'Pair with a short walk to blunt the rise.',
          eveningScore: 4,
          // A long fridge list used to overflow the info pill.
          usedFridgeItems: [
            'quinoa',
            'spinach',
            'chicken thighs',
            'lemons',
            'olive oil',
          ],
          estimatedCostPerServing: r'$2-3/serving',
          // A long question used to be clipped at the card edge.
          suggestedQuestions: [
            'Why is this good for my blood sugar in the evening?',
          ],
        ),
        onAsk: (value, {String? initialQuestion}) {},
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('without onAsk the card has no chips and no tap targets', (
      tester,
    ) async {
      await pumpCard(
        tester,
        recommendation: _recommendation(
          suggestedQuestions: const ['Why is this good?'],
        ),
      );

      expect(find.byKey(const Key('mealQaChip_0')), findsNothing);
      expect(find.byKey(const Key('mealQaStep_0')), findsNothing);
      expect(find.text('Ask about this meal'), findsNothing);
      // The recipe itself must still render exactly as before.
      expect(find.text('Rinse the quinoa.'), findsOneWidget);
      expect(find.text('Tap a line to ask'), findsNothing);
    });
  });

  group('meal Q&A sheet', () {
    var tipSeenCalls = 0;
    setUp(() => tipSeenCalls = 0);

    Future<void> openSheet(
      WidgetTester tester, {
      required MealQaService service,
      MealQuestionScope scope = _stepScope,
      List<MealQaTurn> history = const [],
      ValueChanged<List<MealQaTurn>>? onHistoryChanged,
      bool showFirstRunTip = false,
      String? initialQuestion,
      // Zero spacing keeps these instant; ai_retry_test covers the real 2 s.
      AiRetryPolicy retryPolicy = const AiRetryPolicy(delay: Duration.zero),
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showMealQaSheet(
                  context,
                  meal: _meal,
                  scope: scope,
                  apiKey: 'test-token',
                  history: history,
                  onHistoryChanged: onHistoryChanged ?? (_) {},
                  showFirstRunTip: showFirstRunTip,
                  onTipSeen: () => tipSeenCalls += 1,
                  initialQuestion: initialQuestion,
                  service: service,
                  retryPolicy: retryPolicy,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('quotes the tapped step and answers a typed question', (
      tester,
    ) async {
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient(
          (request) async => _geminiText('It lifts the browned bits.'),
        ),
      );
      await openSheet(tester, service: service);

      expect(find.text('Sear until golden, then deglaze.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('mealQaInput')),
        'What does deglaze mean?',
      );
      await tester.tap(find.byKey(const Key('mealQaSend')));
      await tester.pumpAndSettle();

      expect(find.text('What does deglaze mean?'), findsOneWidget);
      expect(find.text('It lifts the browned bits.'), findsOneWidget);
    });

    testWidgets('auto-submits an initial question from a chip', (tester) async {
      late String capturedBody;
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) async {
          capturedBody = request.body;
          return _geminiText('Quinoa is high in fiber.');
        }),
      );
      await openSheet(
        tester,
        service: service,
        scope: const MealQuestionScope.meal(),
        initialQuestion: 'Why is this good for my blood sugar?',
      );

      expect(capturedBody, contains('Why is this good for my blood sugar?'));
      expect(find.text('Quinoa is high in fiber.'), findsOneWidget);
    });

    testWidgets('keeps a multi-turn transcript and reports it upward', (
      tester,
    ) async {
      var replies = 0;
      final bodies = <String>[];
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) async {
          if (_isChipsRequest(request)) return _geminiText('[]');
          bodies.add(request.body);
          replies += 1;
          return _geminiText('Answer $replies.');
        }),
      );
      List<MealQaTurn> reported = const [];
      await openSheet(
        tester,
        service: service,
        onHistoryChanged: (turns) => reported = turns,
      );

      for (final question in ['First?', 'Second?']) {
        await tester.enterText(find.byKey(const Key('mealQaInput')), question);
        await tester.tap(find.byKey(const Key('mealQaSend')));
        await tester.pumpAndSettle();
      }

      // The newest turn is always on screen; older ones may be scrolled out of
      // the transcript, so assert those through the reported history instead.
      expect(find.text('Answer 2.'), findsOneWidget);
      expect(reported.length, 4);
      expect(reported.map((turn) => turn.isUser), [true, false, true, false]);
      expect(reported.map((turn) => turn.text), [
        'First?',
        'Answer 1.',
        'Second?',
        'Answer 2.',
      ]);
      // The follow-up must carry the first exchange as context.
      expect(bodies.last, contains('Answer 1.'));
    });

    testWidgets('restores a prior transcript when reopened', (tester) async {
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) async => _geminiText('unused')),
      );
      await openSheet(
        tester,
        service: service,
        history: const [
          MealQaTurn.user('Earlier question?'),
          MealQaTurn.agent('Earlier answer.'),
        ],
      );

      expect(find.text('Earlier question?'), findsOneWidget);
      expect(find.text('Earlier answer.'), findsOneWidget);
    });

    testWidgets('shows a final error and recovers on Try again', (
      tester,
    ) async {
      var attempt = 0;
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) async {
          if (_isChipsRequest(request)) return _geminiText('[]');
          attempt += 1;
          // 403 is never retried, so the first failure is the final one.
          if (attempt == 1) return http.Response('boom', 403);
          return _geminiText('Recovered answer.');
        }),
      );
      await openSheet(tester, service: service);

      await tester.enterText(find.byKey(const Key('mealQaInput')), 'Why?');
      await tester.tap(find.byKey(const Key('mealQaSend')));
      await tester.pumpAndSettle();

      expect(attempt, 1, reason: 'a 403 is not retried');
      expect(find.byKey(const Key('mealQaError')), findsOneWidget);

      await tester.tap(find.byKey(const Key('mealQaRetry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mealQaError')), findsNothing);
      expect(find.text('Recovered answer.'), findsOneWidget);
      // Retry must not duplicate the question in the transcript.
      expect(find.text('Why?'), findsOneWidget);
    });

    testWidgets('a hiccup is retried and the answer still arrives', (
      tester,
    ) async {
      var answerCalls = 0;
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) async {
          if (_isChipsRequest(request)) return _geminiText('[]');
          answerCalls += 1;
          if (answerCalls == 1) return http.Response('busy', 503);
          return _geminiText('Deglazing lifts the browned bits.');
        }),
      );
      await openSheet(tester, service: service);

      await tester.enterText(find.byKey(const Key('mealQaInput')), 'Why?');
      await tester.tap(find.byKey(const Key('mealQaSend')));
      await tester.pumpAndSettle();

      expect(answerCalls, 2);
      expect(find.byKey(const Key('mealQaError')), findsNothing);
      expect(find.text('Deglazing lifts the browned bits.'), findsOneWidget);
    });

    testWidgets('the thinking bubble counts the tries', (tester) async {
      final pending = <Completer<http.Response>>[];
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) {
          if (_isChipsRequest(request)) {
            return Future.value(_geminiText('[]'));
          }
          final completer = Completer<http.Response>();
          pending.add(completer);
          return completer.future;
        }),
      );
      await openSheet(tester, service: service);

      await tester.enterText(find.byKey(const Key('mealQaInput')), 'Why?');
      await tester.tap(find.byKey(const Key('mealQaSend')));
      await tester.pump();
      expect(find.textContaining('Retrying'), findsNothing);

      pending.removeAt(0).complete(http.Response('busy', 503));
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(find.text('AI request failed. Retrying 2/5'), findsOneWidget);

      pending.removeAt(0).complete(_geminiText('Because it tastes good.'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Retrying'), findsNothing);
      expect(find.text('Because it tastes good.'), findsOneWidget);
    });

    testWidgets('five failures end in a friendly error', (tester) async {
      var answerCalls = 0;
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) async {
          if (_isChipsRequest(request)) return _geminiText('[]');
          answerCalls += 1;
          return http.Response('busy', 503);
        }),
      );
      await openSheet(tester, service: service);

      await tester.enterText(find.byKey(const Key('mealQaInput')), 'Why?');
      await tester.tap(find.byKey(const Key('mealQaSend')));
      await tester.pumpAndSettle();

      expect(answerCalls, 5);
      expect(
        find.text(
          "Couldn't get an answer after a few tries. "
          'Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('mealQaRetry')), findsOneWidget);
    });

    testWidgets('closing the sheet during a retry stops the attempts', (
      tester,
    ) async {
      final pending = <Completer<http.Response>>[];
      var answerCalls = 0;
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) {
          if (_isChipsRequest(request)) {
            return Future.value(_geminiText('[]'));
          }
          answerCalls += 1;
          final completer = Completer<http.Response>();
          pending.add(completer);
          return completer.future;
        }),
      );
      await openSheet(tester, service: service);

      await tester.enterText(find.byKey(const Key('mealQaInput')), 'Why?');
      await tester.tap(find.byKey(const Key('mealQaSend')));
      await tester.pump();
      pending.removeAt(0).complete(http.Response('busy', 503));
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(find.text('AI request failed. Retrying 2/5'), findsOneWidget);
      expect(answerCalls, 2);

      Navigator.of(tester.element(find.byKey(const Key('mealQaInput')))).pop();
      await tester.pumpAndSettle();

      pending.removeAt(0).complete(http.Response('busy', 503));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      expect(answerCalls, 2, reason: 'the closed sheet stops asking');
      expect(tester.takeException(), isNull);
    });

    testWidgets('suggested-question chips stay single-attempt and silent', (
      tester,
    ) async {
      var chipCalls = 0;
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) async {
          if (_isChipsRequest(request)) {
            chipCalls += 1;
            return http.Response('busy', 503);
          }
          return _geminiText('unused');
        }),
      );
      await openSheet(tester, service: service);

      expect(chipCalls, 1);
      expect(find.byKey(const Key('mealQaError')), findsNothing);
      expect(find.textContaining('Retrying'), findsNothing);
    });

    testWidgets('shows the first-run tip once and reports it was seen', (
      tester,
    ) async {
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) async => _geminiText('[]')),
      );

      await openSheet(tester, service: service, showFirstRunTip: true);

      expect(find.text(_tip), findsOneWidget);
      expect(tipSeenCalls, 1);
    });

    testWidgets('hides the first-run tip once it has been seen', (
      tester,
    ) async {
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) async => _geminiText('[]')),
      );

      await openSheet(tester, service: service);

      expect(find.text(_tip), findsNothing);
      expect(tipSeenCalls, 0);
    });

    testWidgets('a host that calls setState from onTipSeen does not crash', (
      tester,
    ) async {
      // Regression: the sheet is inflated during a build pass, so notifying
      // the host synchronously from initState marked an ancestor dirty
      // mid-build and tripped "setState() called during build".
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) async => _geminiText('[]')),
      );

      await tester.pumpWidget(
        MaterialApp(home: _TipSeenHost(service: service)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(_tip), findsOneWidget);
      expect(find.text('seen: true'), findsOneWidget);
    });

    testWidgets('renders scoped chips and sends one when tapped', (
      tester,
    ) async {
      final bodies = <String>[];
      final service = MealQaService(
        apiKey: 'test-token',
        client: MockClient((request) async {
          bodies.add(request.body);
          if (_isChipsRequest(request)) {
            return _geminiText('["What does deglaze mean?"]');
          }
          return _geminiText('It lifts the browned bits.');
        }),
      );
      await openSheet(tester, service: service);

      expect(find.text('What does deglaze mean?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('mealQaSheetChip_0')));
      await tester.pumpAndSettle();

      expect(find.text('It lifts the browned bits.'), findsOneWidget);
      expect(bodies.last, contains('What does deglaze mean?'));
    });
  });
}

/// Mirrors `_AgentPageState._markQaTipSeen`, which calls setState when the
/// sheet reports that the first-run tip was shown.
class _TipSeenHost extends StatefulWidget {
  const _TipSeenHost({required this.service});
  final MealQaService service;

  @override
  State<_TipSeenHost> createState() => _TipSeenHostState();
}

class _TipSeenHostState extends State<_TipSeenHost> {
  bool _seen = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('seen: $_seen'),
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showMealQaSheet(
                context,
                meal: _meal,
                scope: _stepScope,
                apiKey: 'test-token',
                history: const [],
                onHistoryChanged: (_) {},
                showFirstRunTip: true,
                onTipSeen: () => setState(() => _seen = true),
                service: widget.service,
              ),
              child: const Text('open'),
            ),
          ),
        ],
      ),
    );
  }
}

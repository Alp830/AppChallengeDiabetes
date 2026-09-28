import 'dart:async';
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
                'dishName': 'Slow dish',
                'imagePrompt': 'a slow dish',
                'reason': 'It took a while.',
                'ingredients': ['Rice'],
                'instructions': ['Wait.'],
              },
            ]),
          },
        ],
      },
    },
  ],
});

/// Stands in for the shell: it owns an [AgentPageState] key and a button that
/// runs the same guard a tab switch or sign-out would.
class _AgentHost extends StatefulWidget {
  const _AgentHost({required this.agentKey, required this.onLeaveResult});

  final GlobalKey<AgentPageState> agentKey;
  final ValueChanged<bool> onLeaveResult;

  @override
  State<_AgentHost> createState() => _AgentHostState();
}

class _AgentHostState extends State<_AgentHost> {
  bool _left = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            key: const Key('hostLeave'),
            onPressed: () async {
              final mayLeave = await widget.agentKey.currentState!
                  .confirmLeave();
              widget.onLeaveResult(mayLeave);
              if (mayLeave && mounted) setState(() => _left = true);
            },
            child: const Text('Leave Meals'),
          ),
          Expanded(
            child: _left
                ? const Center(child: Text('Another tab'))
                : AgentPage(
                    key: widget.agentKey,
                    foodItems: const [],
                    userId: 'user-1',
                    geminiApiKey: 'test-key',
                    diabetesEnabled: false,
                    preferencesRepository: FakePreferencesStore(
                      mealQaTipSeen: true,
                    ),
                    savedRecipesStore: InMemorySavedRecipesStore(),
                  ),
          ),
        ],
      ),
    );
  }
}

void main() {
  late http.Client originalClient;
  late Completer<http.Response> pending;
  var requests = 0;

  setUp(() {
    originalClient = GeminiMealService.httpClient;
    requests = 0;
    pending = Completer<http.Response>();
    GeminiMealService.httpClient = MockClient((request) async {
      requests++;
      return pending.future;
    });
    AppEnvironment.setGeminiApiKeyForTesting('test-key');
  });

  tearDown(() {
    GeminiMealService.httpClient = originalClient;
    AppEnvironment.setGeminiApiKeyForTesting('');
  });

  Future<GlobalKey<AgentPageState>> pumpHost(
    WidgetTester tester, {
    required List<bool> results,
  }) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final agentKey = GlobalKey<AgentPageState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: _AgentHost(agentKey: agentKey, onLeaveResult: results.add),
      ),
    );
    await tester.pump();
    return agentKey;
  }

  Future<void> startRequest(WidgetTester tester) async {
    // Created here, inside the test's async zone, so its continuations run
    // when the tester pumps.
    pending = Completer<http.Response>();
    await tester.tap(find.byKey(const Key('recommendMealButton')));
    await tester.pump();
  }

  testWidgets('leaving with nothing in flight asks nothing', (tester) async {
    final results = <bool>[];
    await pumpHost(tester, results: results);

    await tester.tap(find.byKey(const Key('hostLeave')));
    await tester.pumpAndSettle();

    expect(find.text('Stop waiting for your meal idea?'), findsNothing);
    expect(results, [true]);
  });

  testWidgets('leaving while a recipe loads asks, and Keep waiting stays', (
    tester,
  ) async {
    final results = <bool>[];
    final agentKey = await pumpHost(tester, results: results);
    await startRequest(tester);
    expect(agentKey.currentState!.isLoadingRecommendation, isTrue);

    await tester.tap(find.byKey(const Key('hostLeave')));
    await tester.pumpAndSettle();

    expect(find.text('Stop waiting for your meal idea?'), findsOneWidget);
    expect(
      find.text(
        "It's still on its way. If you leave now, we'll stop this request.",
      ),
      findsOneWidget,
    );
    // The copy is about this request only.
    expect(find.textContaining('fridge'), findsNothing);
    expect(find.textContaining('saved recipe'), findsNothing);

    await tester.tap(find.byKey(const Key('agentKeepWaiting')));
    await tester.pumpAndSettle();
    expect(results, [false]);
    expect(find.text('Another tab'), findsNothing);

    // The answer still arrives for the user who waited.
    pending.complete(http.Response(_modelReply(), 200));
    await tester.pumpAndSettle();
    expect(find.byType(MealRecommendationCard), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Slow dish'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    expect(find.text('Slow dish'), findsOneWidget);
  });

  testWidgets('Leave cancels the request and a late reply never shows', (
    tester,
  ) async {
    final results = <bool>[];
    final agentKey = await pumpHost(tester, results: results);
    await startRequest(tester);

    await tester.tap(find.byKey(const Key('hostLeave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agentLeave')));
    await tester.pumpAndSettle();

    expect(results, [true]);
    expect(find.text('Another tab'), findsOneWidget);

    pending.complete(http.Response(_modelReply(), 200));
    await tester.pumpAndSettle();
    expect(find.text('Slow dish'), findsNothing);
    expect(requests, 1, reason: 'leaving starts nothing new');
    expect(agentKey.currentState, isNull);
  });

  testWidgets('cancelling clears the loading state and drops the result', (
    tester,
  ) async {
    final results = <bool>[];
    final agentKey = await pumpHost(tester, results: results);
    await startRequest(tester);

    agentKey.currentState!.cancelRecommendation();
    await tester.pump();
    expect(agentKey.currentState!.isLoadingRecommendation, isFalse);

    pending.complete(http.Response(_modelReply(), 200));
    await tester.pumpAndSettle();
    expect(find.text('Slow dish'), findsNothing);
    // And leaving now needs no confirmation.
    await tester.tap(find.byKey(const Key('hostLeave')));
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('a cancelled request does not leave an error behind', (
    tester,
  ) async {
    final results = <bool>[];
    final agentKey = await pumpHost(tester, results: results);
    await startRequest(tester);

    agentKey.currentState!.cancelRecommendation();
    await tester.pump();
    // The request fails after the user gave up on it.
    pending.complete(http.Response('gateway timeout', 504));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't get a meal idea right now."), findsNothing);
    expect(find.byKey(const Key('loadErrorRetry')), findsNothing);
  });
}

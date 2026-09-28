import 'dart:typed_data';

import 'package:diabetes/ai/ai_retry.dart';
import 'package:diabetes/ai/ai_retry_status.dart';
import 'package:diabetes/design/app_theme.dart';
import 'package:diabetes/fridge/fridge_scan_dialog.dart';
import 'package:diabetes/exercise/data/today_todo_repository.dart';
import 'package:diabetes/home/mvp_home_page.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('Retry status row', (tester) async {
    await pumpAt200(
      tester,
      const Column(children: [AiRetryStatus(attempt: 3, maxAttempts: 5)]),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('AI request failed. Retrying 3/5'), findsOneWidget);
  });

  testWidgets('Fridge scan dialog, running and failed', (tester) async {
    await pumpAt200(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<FridgeScanResult>(
            context: context,
            barrierDismissible: false,
            builder: (_) => FridgeScanDialog(
              imageBytes: Uint8List(0),
              retryPolicy: const AiRetryPolicy(
                maxAttempts: 1,
                delay: Duration.zero,
              ),
              detect: (_) async =>
                  throw AiRequestException.fromStatus(503, 'busy'),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(find.text("Couldn't read the photo"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:diabetes/design/app_theme.dart';
import 'package:diabetes/exercise/data/today_todo_repository.dart';
import 'package:diabetes/home/mvp_home_page.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> check(WidgetTester tester, Widget home) async {
  final semantics = tester.ensureSemantics();
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: home));
  await tester.pump();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  semantics.dispose();
}

void main() {
  testWidgets('Auth', (tester) => check(tester, const AuthPage()));

  testWidgets(
    'Fridge',
    (tester) => check(
      tester,
      Scaffold(
        body: FridgePage(
          initialItems: const [
            StoredFoodItem(
              id: 'a',
              foodItem: FoodItem(
                name: 'Milk',
                amount: '1',
                foodType: FoodType.dairy,
              ),
            ),
          ],
          onCommit: (_) async {},
        ),
      ),
    ),
  );

  testWidgets(
    'Fridge empty',
    (tester) => check(
      tester,
      Scaffold(
        body: FridgePage(initialItems: const [], onCommit: (_) async {}),
      ),
    ),
  );

  testWidgets(
    'Home',
    (tester) => check(
      tester,
      Scaffold(
        body: MvpHomePage(
          userId: 'u',
          todoStateStream: Stream.value(
            const TodayTodoState(
              isInitialized: true,
              items: [TodayTodo(id: 't', name: 'Walk')],
            ),
          ),
          onSaveTodos: (_) async {},
          onOpenFridge: () {},
          fridgeItemCount: 3,
        ),
      ),
    ),
  );

  testWidgets(
    'Agent',
    (tester) => check(tester, const Scaffold(body: AgentPage(foodItems: []))),
  );
}

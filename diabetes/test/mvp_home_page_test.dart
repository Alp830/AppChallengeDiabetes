import 'package:diabetes/exercise/data/today_todo_repository.dart';
import 'package:diabetes/home/mvp_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MVP home opens the fridge and manages the daily checklist', (
    tester,
  ) async {
    var fridgeOpenCount = 0;
    var savedItems = <TodayTodo>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MvpHomePage(
            userId: 'user-1',
            userName: 'Lina',
            now: DateTime(2026, 7, 21),
            todoStateStream: Stream.value(
              const TodayTodoState(isInitialized: true, items: []),
            ),
            onSaveTodos: (items) async => savedItems = List.of(items),
            onOpenFridge: () => fridgeOpenCount++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('mvpHomePage')), findsOneWidget);
    expect(find.text('No tasks yet'), findsOneWidget);

    await tester.tap(find.text("What's in your fridge"));
    expect(fridgeOpenCount, 1);

    await tester.tap(find.byKey(const Key('mvpAddTodoButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('mvpTodoNameField')),
      'Check fridge',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Check fridge'), findsOneWidget);
    expect(savedItems.single.name, 'Check fridge');

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(savedItems.single.isCompleted, isTrue);

    await tester.tap(find.byTooltip('Remove Check fridge'));
    await tester.pump();
    expect(savedItems, isEmpty);
  });
}

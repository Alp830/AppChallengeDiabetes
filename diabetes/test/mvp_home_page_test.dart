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
    await tester.pumpAndSettle(); // snackbar appears after the async save
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(savedItems.single.name, 'Check fridge');
  });

  Widget home({
    required Stream<TodayTodoState> stream,
    int? fridgeItemCount,
    int expiringCount = 0,
  }) => MaterialApp(
    home: Scaffold(
      body: MvpHomePage(
        userId: 'user-1',
        now: DateTime(2026, 7, 21),
        todoStateStream: stream,
        onSaveTodos: (_) async {},
        onOpenFridge: () {},
        fridgeItemCount: fridgeItemCount,
        expiringCount: expiringCount,
      ),
    ),
  );

  testWidgets('banner summarizes the fridge', (tester) async {
    await tester.pumpWidget(
      home(
        stream: Stream.value(
          const TodayTodoState(isInitialized: true, items: []),
        ),
        fridgeItemCount: 5,
        expiringCount: 2,
      ),
    );
    await tester.pump();
    expect(find.text('5 items · 2 expiring soon'), findsOneWidget);
  });

  testWidgets('tapping a task opens the edit dialog', (tester) async {
    await tester.pumpWidget(
      home(
        stream: Stream.value(
          const TodayTodoState(
            isInitialized: true,
            items: [TodayTodo(id: 't1', name: 'Walk')],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Walk'));
    await tester.pumpAndSettle();
    expect(find.text('Edit task'), findsOneWidget);
  });

  testWidgets('loading shows a skeleton, errors offer retry', (tester) async {
    await tester.pumpWidget(home(stream: const Stream<TodayTodoState>.empty()));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading your checklist'), findsOneWidget);

    // Unmount first: the page reads its stream once, in initState.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(home(stream: Stream.error(Exception('offline'))));
    await tester.pump();
    expect(find.byKey(const Key('loadErrorRetry')), findsOneWidget);
  });
}

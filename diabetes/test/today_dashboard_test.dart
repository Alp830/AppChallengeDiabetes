import 'package:diabetes/exercise/models/workout_session.dart';
import 'package:diabetes/exercise/data/today_todo_repository.dart';
import 'package:diabetes/exercise/screens/today_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 12, 9);

  testWidgets('shows the empty activity state for today', (tester) async {
    await tester.pumpWidget(
      _app(
        now: now,
        today: const [],
        recent: const [],
        onOpenExercise: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Good morning, Mustafa'), findsOneWidget);
    expect(find.text('Sunday, July 12'), findsOneWidget);
    expect(find.text('0 of 30 minutes today'), findsOneWidget);
    expect(find.text('No workouts recorded today yet.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(
        'Complete at least three workouts to start seeing patterns in your activity.',
      ),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(
        'Complete at least three workouts to start seeing patterns in your activity.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('totals today and displays only the newest three workouts', (
    tester,
  ) async {
    final sessions = [
      _session('4', 'Evening walk', now.add(const Duration(hours: 8)), 600),
      _session('3', 'Yoga', now.add(const Duration(hours: 6)), 300),
      _session('2', 'Strength', now.add(const Duration(hours: 4)), 600),
      _session('1', 'Morning walk', now.add(const Duration(hours: 1)), 600),
    ];

    await tester.pumpWidget(
      _app(
        now: now,
        today: sessions,
        recent: sessions,
        onOpenExercise: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('35 of 30 minutes today'), findsOneWidget);
    expect(find.text('Daily goal complete'), findsOneWidget);
    expect(find.text('Evening walk'), findsOneWidget);
    expect(find.text('Yoga'), findsOneWidget);
    expect(find.text('Strength'), findsOneWidget);
    expect(find.text('Morning walk'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Your recent routine'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Your recent routine'), findsOneWidget);
  });

  testWidgets('activity actions open the existing Exercise tab callback', (
    tester,
  ) async {
    var openCount = 0;
    final session = _session('1', 'Morning walk', now, 600);
    await tester.pumpWidget(
      _app(
        now: now,
        today: [session],
        recent: [session],
        onOpenExercise: () => openCount++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue activity'));
    expect(openCount, 1);

    await tester.ensureVisible(find.text('Morning walk'));
    await tester.tap(find.text('Morning walk'));
    expect(openCount, 2);
  });

  testWidgets('shows a friendly message when activity loading fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TodayDashboard(
          userId: 'user-1',
          onOpenExercise: () {},
          now: now,
          recentSessionsStream: Stream.error(Exception('permission-denied')),
          todaySessionsStream: Stream.value(const []),
          todoStateStream: Stream.value(
            const TodayTodoState(isInitialized: true, items: []),
          ),
          onSaveTodos: (_) async {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Could not load today’s activity. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('permission-denied'), findsNothing);
  });

  testWidgets('daily tasks can be added, renamed, checked, and removed', (
    tester,
  ) async {
    final savedLists = <List<TodayTodo>>[];
    await tester.pumpWidget(
      _app(
        now: now,
        today: const [],
        recent: const [],
        todos: const [],
        onSaveTodos: (items) async => savedLists.add(List.of(items)),
        onOpenExercise: () {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('addTodoButton')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('addTodoButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('todoNameField')), 'Drink water');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Drink water'), findsOneWidget);

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('todoNameField')), 'Fill bottle');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Fill bottle'), findsOneWidget);
    expect(find.text('Drink water'), findsNothing);

    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(savedLists.last.single.isCompleted, isTrue);

    await tester.tap(find.byTooltip('Remove Fill bottle'));
    await tester.pump();
    expect(find.text('No tasks yet. Add one for today.'), findsOneWidget);
    expect(savedLists.last, isEmpty);
  });

  testWidgets('daily tasks can be reordered', (tester) async {
    final savedLists = <List<TodayTodo>>[];
    const todos = [
      TodayTodo(id: 'a', name: 'First'),
      TodayTodo(id: 'b', name: 'Second'),
      TodayTodo(id: 'c', name: 'Third'),
    ];
    await tester.pumpWidget(
      _app(
        now: now,
        today: const [],
        recent: const [],
        todos: todos,
        onSaveTodos: (items) async => savedLists.add(List.of(items)),
        onOpenExercise: () {},
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('todayTodoList')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    tester.widget<ReorderableListView>(find.byKey(const Key('todayTodoList')))
      .onReorderItem!(0, 2);
    await tester.pump();

    expect(savedLists.last.map((item) => item.id), ['b', 'c', 'a']);
  });
}

Widget _app({
  required DateTime now,
  required List<WorkoutSession> today,
  required List<WorkoutSession> recent,
  required VoidCallback onOpenExercise,
  List<TodayTodo>? todos,
  Future<void> Function(List<TodayTodo>)? onSaveTodos,
}) {
  return MaterialApp(
    home: Scaffold(
      body: TodayDashboard(
        userId: 'user-1',
        userName: 'Mustafa',
        onOpenExercise: onOpenExercise,
        now: now,
        todaySessionsStream: Stream.value(today),
        recentSessionsStream: Stream.value(recent),
        todoStateStream: Stream.value(
          TodayTodoState(isInitialized: true, items: todos ?? const []),
        ),
        onSaveTodos: onSaveTodos ?? (_) async {},
      ),
    ),
  );
}

WorkoutSession _session(
  String id,
  String name,
  DateTime startedAt,
  int seconds,
) {
  return WorkoutSession(
    id: id,
    activityType: WorkoutActivityType.walking,
    activityName: name,
    plannedDurationMinutes: (seconds / 60).round(),
    actualDurationSeconds: seconds,
    intensity: WorkoutIntensity.moderate,
    startedAt: startedAt,
    completedAt: startedAt.add(Duration(seconds: seconds)),
    preWorkout: const PreWorkoutCheck(
      glucoseUnit: 'mg/dL',
      usesHypoglycemiaRiskMedication: false,
      hasWater: true,
      hasFastCarbs: true,
      completedFootCheck: true,
      hasConcerningSymptoms: false,
    ),
    postWorkout: const PostWorkoutReview(
      glucoseUnit: 'mg/dL',
      energyLevel: 3,
      mood: 3,
      perceivedDifficulty: 2,
      experiencedLow: false,
    ),
    source: WorkoutSource.manual,
  );
}

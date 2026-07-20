import 'package:diabetes/cgm/screens/glucose_settings_page.dart';
import 'package:diabetes/exercise/data/exercise_repository.dart';
import 'package:diabetes/exercise/models/exercise_profile.dart';
import 'package:diabetes/exercise/models/workout_session.dart';
import 'package:diabetes/exercise/screens/exercise_page.dart';
import 'package:diabetes/exercise/screens/movement_lab_page.dart';
import 'package:diabetes/main.dart';
import 'package:diabetes/meals/screens/meal_lab_page.dart';
import 'package:diabetes/navigation/app_feature_navigation.dart';
import 'package:diabetes/settings/data/app_preferences_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('disabled diabetes navigation does not push a route', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: _NavigationHarness(diabetesEnabled: false)),
    );

    await tester.tap(find.text('Open guarded page'));
    await tester.pumpAndSettle();

    expect(find.text('Guarded destination'), findsNothing);
    expect(find.text('Navigation host'), findsOneWidget);
  });

  testWidgets('enabled diabetes navigation pushes the existing route', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: _NavigationHarness(diabetesEnabled: true)),
    );

    await tester.tap(find.text('Open guarded page'));
    await tester.pumpAndSettle();

    expect(find.text('Guarded destination'), findsOneWidget);
  });

  testWidgets(
    'disabled Agent hides Meal Lab and keeps meal logging prominent',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentPage(
              foodItems: const [],
              userId: 'user-1',
              diabetesEnabled: false,
              preferencesRepository: _StaticPreferencesStore(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Meal Lab'), findsNothing);
      expect(find.text('Log Meal'), findsOneWidget);
      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'Log Meal')).width,
        greaterThan(500),
      );
    },
  );

  testWidgets('enabled Agent retains the Meal Lab entry point', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentPage(
            foodItems: const [],
            userId: 'user-1',
            diabetesEnabled: true,
            preferencesRepository: _StaticPreferencesStore(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Meal Lab'), findsOneWidget);
    expect(find.text('Log Meal'), findsOneWidget);
  });

  testWidgets('Exercise hides Movement Lab only in disabled mode', (
    tester,
  ) async {
    final repository = _FakeExerciseRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExercisePage(
            userId: 'user-1',
            repository: repository,
            diabetesEnabled: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open Movement Lab'), findsNothing);
    expect(find.text('Start a workout'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExercisePage(
            userId: 'user-1',
            repository: repository,
            diabetesEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open Movement Lab'), findsOneWidget);
  });

  testWidgets('disabled diabetes-only pages create no repositories or UI', (
    tester,
  ) async {
    var glucoseSettingsRepositoryCreated = false;
    var movementExerciseRepositoryCreated = false;
    var movementGlucoseRepositoryCreated = false;

    await tester.pumpWidget(
      MaterialApp(
        home: GlucoseSettingsPage(
          userId: 'user-1',
          diabetesEnabled: false,
          repositoryFactory: () {
            glucoseSettingsRepositoryCreated = true;
            throw StateError('disabled repository factory was called');
          },
        ),
      ),
    );
    await tester.pump();
    expect(glucoseSettingsRepositoryCreated, isFalse);
    expect(find.textContaining('Libre'), findsNothing);
    expect(find.textContaining('Glucose'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: MovementLabPage(
          userId: 'user-1',
          diabetesEnabled: false,
          exerciseRepositoryFactory: () {
            movementExerciseRepositoryCreated = true;
            throw StateError('disabled exercise repository factory was called');
          },
          glucoseRepositoryFactory: () {
            movementGlucoseRepositoryCreated = true;
            throw StateError('disabled glucose repository factory was called');
          },
        ),
      ),
    );
    await tester.pump();
    expect(movementExerciseRepositoryCreated, isFalse);
    expect(movementGlucoseRepositoryCreated, isFalse);
    expect(find.text('Movement Lab'), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: MealLabPage(userId: 'user-1', diabetesEnabled: false),
      ),
    );
    await tester.pump();
    expect(find.text('Meal Lab'), findsNothing);
    expect(find.byKey(const Key('diabetesFeatureDisabled')), findsOneWidget);
  });
}

class _NavigationHarness extends StatelessWidget {
  const _NavigationHarness({required this.diabetesEnabled});

  final bool diabetesEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Navigation host')),
      body: Center(
        child: FilledButton(
          onPressed: () => AppFeatureNavigation.pushDiabetesPage<void>(
            context,
            diabetesEnabled: diabetesEnabled,
            builder: (context) => const Scaffold(
              body: Center(child: Text('Guarded destination')),
            ),
          ),
          child: const Text('Open guarded page'),
        ),
      ),
    );
  }
}

class _StaticPreferencesStore implements AppPreferencesStore {
  @override
  Future<void> saveMealBalanceAgentEnabled(String userId, bool enabled) async {}

  @override
  Stream<bool> watchMealBalanceAgentEnabled(String userId) =>
      Stream<bool>.value(false);
}

class _FakeExerciseRepository implements ExerciseRepository {
  @override
  Future<void> deleteSession(String userId, String sessionId) async {}

  @override
  Future<ExerciseProfile> getProfile(String userId) async =>
      ExerciseProfile.defaults;

  @override
  Future<String> saveCompletedSession(
    String userId,
    WorkoutSession session,
  ) async => 'session-1';

  @override
  Future<void> saveProfile(String userId, ExerciseProfile profile) async {}

  @override
  Stream<ExerciseProfile> watchProfile(String userId) =>
      Stream<ExerciseProfile>.value(ExerciseProfile.defaults);

  @override
  Stream<List<WorkoutSession>> watchRecentSessions(
    String userId, {
    int limit = 50,
  }) => Stream<List<WorkoutSession>>.value(const []);

  @override
  Stream<List<WorkoutSession>> watchSessionsForDay(
    String userId,
    DateTime localDay,
  ) => Stream<List<WorkoutSession>>.value(const []);
}

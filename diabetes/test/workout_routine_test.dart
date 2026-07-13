import 'package:diabetes/exercise/models/workout_routine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('built-in routines have valid durations and steps', () {
    expect(builtInWorkoutRoutines, hasLength(4));

    for (final routine in builtInWorkoutRoutines) {
      expect(routine.id, isNotEmpty);
      expect(routine.steps, isNotEmpty);
      expect(routine.durationSeconds, greaterThan(0));
      expect(routine.steps.every((step) => step.durationSeconds > 0), isTrue);
    }
  });

  test('the beginner walk lasts ten minutes', () {
    final walk = builtInWorkoutRoutines.firstWhere(
      (routine) => routine.id == 'beginner_walk_10',
    );

    expect(walk.durationSeconds, 600);
    expect(walk.durationMinutes, 10);
  });
}

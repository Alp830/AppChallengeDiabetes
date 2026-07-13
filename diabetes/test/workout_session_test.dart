import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diabetes/exercise/models/workout_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads a completed workout from Firestore-shaped data', () {
    final startedAt = DateTime(2026, 7, 12, 10);
    final completedAt = startedAt.add(const Duration(minutes: 12));
    final session = WorkoutSession.fromFirestore('session-1', {
      'activityType': 'walking',
      'activityName': 'Morning walk',
      'plannedDurationMinutes': 10,
      'actualDurationSeconds': 720,
      'intensity': 'moderate',
      'startedAt': Timestamp.fromDate(startedAt),
      'completedAt': Timestamp.fromDate(completedAt),
      'source': 'manual',
      'preWorkout': {
        'glucoseValue': 132,
        'glucoseUnit': 'mg/dL',
        'usesHypoglycemiaRiskMedication': false,
        'hasWater': true,
        'hasFastCarbs': false,
        'completedFootCheck': true,
        'hasConcerningSymptoms': false,
      },
      'postWorkout': {
        'glucoseValue': 118,
        'glucoseUnit': 'mg/dL',
        'energyLevel': 4,
        'mood': 4,
        'perceivedDifficulty': 2,
        'experiencedLow': false,
      },
    });

    expect(session.id, 'session-1');
    expect(session.activityType, WorkoutActivityType.walking);
    expect(session.actualDurationSeconds, 720);
    expect(session.preWorkout.glucoseValue, 132);
    expect(session.postWorkout.glucoseValue, 118);
  });

  test('serializes workout values and nested reviews', () {
    final startedAt = DateTime(2026, 7, 12, 10);
    final session = WorkoutSession(
      id: '',
      activityType: WorkoutActivityType.strength,
      activityName: 'Beginner strength',
      plannedDurationMinutes: 20,
      actualDurationSeconds: 1100,
      intensity: WorkoutIntensity.light,
      startedAt: startedAt,
      completedAt: startedAt.add(const Duration(seconds: 1100)),
      preWorkout: const PreWorkoutCheck(
        glucoseUnit: 'mg/dL',
        usesHypoglycemiaRiskMedication: false,
        hasWater: true,
        hasFastCarbs: false,
        completedFootCheck: true,
        hasConcerningSymptoms: false,
      ),
      postWorkout: const PostWorkoutReview(
        glucoseUnit: 'mg/dL',
        energyLevel: 4,
        mood: 5,
        perceivedDifficulty: 3,
        experiencedLow: false,
      ),
      source: WorkoutSource.guidedRoutine,
    );

    final data = session.toFirestore();

    expect(data['activityType'], 'strength');
    expect(data['status'], 'completed');
    expect(data['source'], 'guidedRoutine');
    expect((data['postWorkout'] as Map)['mood'], 5);
  });
}

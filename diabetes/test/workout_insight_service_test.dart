import 'package:diabetes/exercise/models/workout_session.dart';
import 'package:diabetes/exercise/services/workout_insight_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = WorkoutInsightService();

  WorkoutSession session(
    int index, {
    double? before,
    double? after,
    bool experiencedLow = false,
    WorkoutSource source = WorkoutSource.manual,
  }) {
    final start = DateTime(2026, 7, 12).subtract(Duration(days: index));
    return WorkoutSession(
      id: '$index',
      activityType: WorkoutActivityType.walking,
      activityName: 'Walk',
      plannedDurationMinutes: 10,
      actualDurationSeconds: 600,
      intensity: WorkoutIntensity.moderate,
      startedAt: start,
      completedAt: start.add(const Duration(minutes: 10)),
      preWorkout: PreWorkoutCheck(
        glucoseValue: before,
        glucoseUnit: 'mg/dL',
        usesHypoglycemiaRiskMedication: false,
        hasWater: true,
        hasFastCarbs: true,
        completedFootCheck: true,
        hasConcerningSymptoms: false,
      ),
      postWorkout: PostWorkoutReview(
        glucoseValue: after,
        glucoseUnit: 'mg/dL',
        energyLevel: 3,
        mood: 3,
        perceivedDifficulty: 2,
        experiencedLow: experiencedLow,
      ),
      source: source,
    );
  }

  test('requires at least three sessions', () {
    expect(service.buildInsights([session(0), session(1)]), isEmpty);
  });

  test('summarizes paired glucose without claiming causation', () {
    final insights = service.buildInsights([
      session(0, before: 140, after: 120),
      session(1, before: 130, after: 115),
      session(2, before: 135, after: 125),
    ]);

    final glucoseInsight = insights.firstWhere(
      (insight) => insight.title == 'Logged glucose pattern',
    );
    expect(glucoseInsight.message, contains('lower'));
    expect(glucoseInsight.message, contains('observation'));
  });

  test('calls attention to recorded low symptoms', () {
    final insights = service.buildInsights([
      session(0, experiencedLow: true),
      session(1),
      session(2),
    ]);

    expect(
      insights.any((insight) => insight.title == 'Review recorded lows'),
      isTrue,
    );
  });
}

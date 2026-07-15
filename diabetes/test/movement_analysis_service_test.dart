import 'package:diabetes/cgm/models/glucose_models.dart';
import 'package:diabetes/exercise/models/workout_session.dart';
import 'package:diabetes/exercise/services/movement_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summarizes during and two-hour workout glucose context', () {
    final start = DateTime(2026, 7, 13, 18);
    final session = _session(start);
    final readings = [
      _reading(start.subtract(const Duration(minutes: 15)), 140),
      _reading(start, 138),
      _reading(start.add(const Duration(minutes: 30)), 120),
      _reading(start.add(const Duration(hours: 2, minutes: 30)), 110),
      _reading(DateTime(2026, 7, 14, 1), 105),
      _reading(DateTime(2026, 7, 14, 3), 108),
    ];
    final response = const MovementAnalysisService().response(session, readings);

    expect(response.hasCoverage, isTrue);
    expect(response.duringChange, lessThan(0));
    expect(response.twoHourChange, lessThan(0));
    expect(response.overnightAverageMgDl, closeTo(106.5, .1));
  });

  test('returns incomplete when baseline is unavailable', () {
    final start = DateTime(2026, 7, 13, 10);
    final response = const MovementAnalysisService().response(
      _session(start),
      [_reading(start.add(const Duration(minutes: 30)), 120)],
    );
    expect(response.hasCoverage, isFalse);
  });
}

WorkoutSession _session(DateTime start) => WorkoutSession(
  id: 'workout',
  activityType: WorkoutActivityType.walking,
  activityName: 'Walk',
  plannedDurationMinutes: 30,
  actualDurationSeconds: 1800,
  intensity: WorkoutIntensity.moderate,
  startedAt: start,
  completedAt: start.add(const Duration(minutes: 30)),
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

GlucoseReading _reading(DateTime timestamp, double value) => GlucoseReading(
  id: timestamp.toIso8601String(),
  timestamp: timestamp,
  valueMgDl: value,
  originalValue: value,
  originalUnit: 'mg/dL',
  source: GlucoseSource.libreView,
  recordType: GlucoseRecordType.historic,
);

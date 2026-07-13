import 'package:diabetes/exercise/models/workout_session.dart';
import 'package:diabetes/exercise/services/exercise_safety_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = ExerciseSafetyService();

  PreWorkoutCheck check({
    double? glucose = 120,
    bool usesRiskMedication = false,
    bool hasWater = true,
    bool hasFastCarbs = true,
    bool completedFootCheck = true,
    bool hasConcerningSymptoms = false,
  }) {
    return PreWorkoutCheck(
      glucoseValue: glucose,
      glucoseUnit: 'mg/dL',
      usesHypoglycemiaRiskMedication: usesRiskMedication,
      hasWater: hasWater,
      hasFastCarbs: hasFastCarbs,
      completedFootCheck: completedFootCheck,
      hasConcerningSymptoms: hasConcerningSymptoms,
    );
  }

  test('returns ready when the checklist is complete', () {
    final result = service.evaluate(check());

    expect(result.severity, SafetySeverity.ready);
    expect(result.messages, hasLength(1));
  });

  test('returns cautions for missing workout supplies', () {
    final result = service.evaluate(
      check(
        usesRiskMedication: true,
        hasWater: false,
        hasFastCarbs: false,
        completedFootCheck: false,
      ),
    );

    expect(result.severity, SafetySeverity.caution);
    expect(result.messages, hasLength(3));
  });

  test('stops a workout when concerning symptoms are reported', () {
    final result = service.evaluate(check(hasConcerningSymptoms: true));

    expect(result.severity, SafetySeverity.stop);
    expect(result.messages.join(' '), contains('Do not begin'));
  });

  test('missing glucose is informational rather than blocking', () {
    final result = service.evaluate(check(glucose: null));

    expect(result.severity, SafetySeverity.caution);
    expect(result.messages.join(' '), contains('No glucose reading'));
  });
}

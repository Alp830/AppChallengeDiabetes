import 'package:diabetes/app_features.dart';
import 'package:diabetes/exercise/models/workout_session.dart';
import 'package:diabetes/exercise/services/exercise_safety_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diabetes support defaults off', () {
    expect(AppFeatures.diabetesEnabled, isFalse);
  });

  test('non-diabetes workout safety does not request glucose supplies', () {
    final result = const ExerciseSafetyService().evaluate(
      const PreWorkoutCheck(
        glucoseUnit: 'mg/dL',
        usesHypoglycemiaRiskMedication: true,
        hasWater: true,
        hasFastCarbs: false,
        completedFootCheck: false,
        hasConcerningSymptoms: false,
      ),
      diabetesEnabled: false,
    );

    expect(result.severity, SafetySeverity.ready);
    expect(result.messages.join(' '), isNot(contains('glucose')));
    expect(result.messages.join(' '), isNot(contains('carbohydrate')));
  });
}

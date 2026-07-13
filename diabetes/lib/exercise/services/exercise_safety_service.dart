import '../models/workout_session.dart';

enum SafetySeverity { ready, caution, stop }

class SafetyResult {
  const SafetyResult({required this.severity, required this.messages});

  final SafetySeverity severity;
  final List<String> messages;
}

class ExerciseSafetyService {
  const ExerciseSafetyService();

  SafetyResult evaluate(PreWorkoutCheck check) {
    if (check.hasConcerningSymptoms) {
      return const SafetyResult(
        severity: SafetySeverity.stop,
        messages: [
          'Do not begin this workout while you have chest pain, severe dizziness, confusion, or unusual weakness.',
          'Follow your emergency care plan or seek medical help if symptoms are severe or worsening.',
        ],
      );
    }

    final messages = <String>[];
    if (!check.hasWater) {
      messages.add('Bring water and stay hydrated during your workout.');
    }
    if (check.usesHypoglycemiaRiskMedication && !check.hasFastCarbs) {
      messages.add(
        'Bring your usual fast-acting carbohydrate before starting.',
      );
    }
    if (!check.completedFootCheck) {
      messages.add(
        'Check your footwear and feet before weight-bearing exercise.',
      );
    }
    if (check.glucoseValue == null) {
      messages.add(
        'No glucose reading was entered. Follow the monitoring plan given by your care team.',
      );
    }

    if (messages.isEmpty) {
      return const SafetyResult(
        severity: SafetySeverity.ready,
        messages: [
          'Your checklist is complete. Remember to listen to your body.',
        ],
      );
    }

    return SafetyResult(severity: SafetySeverity.caution, messages: messages);
  }
}

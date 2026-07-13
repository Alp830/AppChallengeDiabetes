class ExerciseProfile {
  const ExerciseProfile({
    required this.weeklyMinutesGoal,
    required this.weeklyStrengthGoal,
    required this.glucoseUnit,
    required this.preWorkoutCheckEnabled,
  });

  static const defaults = ExerciseProfile(
    weeklyMinutesGoal: 150,
    weeklyStrengthGoal: 2,
    glucoseUnit: 'mg/dL',
    preWorkoutCheckEnabled: true,
  );

  final int weeklyMinutesGoal;
  final int weeklyStrengthGoal;
  final String glucoseUnit;
  final bool preWorkoutCheckEnabled;

  Map<String, dynamic> toFirestore() => {
    'weeklyMinutesGoal': weeklyMinutesGoal,
    'weeklyStrengthGoal': weeklyStrengthGoal,
    'glucoseUnit': glucoseUnit,
    'preWorkoutCheckEnabled': preWorkoutCheckEnabled,
  };

  factory ExerciseProfile.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) {
      return defaults;
    }
    return ExerciseProfile(
      weeklyMinutesGoal:
          (data['weeklyMinutesGoal'] as num?)?.toInt() ??
          defaults.weeklyMinutesGoal,
      weeklyStrengthGoal:
          (data['weeklyStrengthGoal'] as num?)?.toInt() ??
          defaults.weeklyStrengthGoal,
      glucoseUnit: data['glucoseUnit'] as String? ?? defaults.glucoseUnit,
      preWorkoutCheckEnabled:
          data['preWorkoutCheckEnabled'] as bool? ??
          defaults.preWorkoutCheckEnabled,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

enum WorkoutActivityType {
  walking,
  running,
  cycling,
  swimming,
  strength,
  chairExercise,
  yoga,
  stretching,
  sports,
  householdWork,
  errands,
  activeWork,
  movementBreak,
  custom,
}

enum WorkoutIntensity { light, moderate, vigorous }

enum WorkoutSource { manual, guidedRoutine, postMealWalk }

class PreWorkoutCheck {
  const PreWorkoutCheck({
    this.glucoseValue,
    required this.glucoseUnit,
    this.minutesSinceMeal,
    required this.usesHypoglycemiaRiskMedication,
    required this.hasWater,
    required this.hasFastCarbs,
    required this.completedFootCheck,
    required this.hasConcerningSymptoms,
    this.notes,
  });

  final double? glucoseValue;
  final String glucoseUnit;
  final int? minutesSinceMeal;
  final bool usesHypoglycemiaRiskMedication;
  final bool hasWater;
  final bool hasFastCarbs;
  final bool completedFootCheck;
  final bool hasConcerningSymptoms;
  final String? notes;

  Map<String, dynamic> toFirestore() => {
    if (glucoseValue != null) 'glucoseValue': glucoseValue,
    'glucoseUnit': glucoseUnit,
    if (minutesSinceMeal != null) 'minutesSinceMeal': minutesSinceMeal,
    'usesHypoglycemiaRiskMedication': usesHypoglycemiaRiskMedication,
    'hasWater': hasWater,
    'hasFastCarbs': hasFastCarbs,
    'completedFootCheck': completedFootCheck,
    'hasConcerningSymptoms': hasConcerningSymptoms,
    if (notes?.isNotEmpty ?? false) 'notes': notes,
  };

  factory PreWorkoutCheck.fromFirestore(Map<String, dynamic> data) {
    return PreWorkoutCheck(
      glucoseValue: (data['glucoseValue'] as num?)?.toDouble(),
      glucoseUnit: data['glucoseUnit'] as String? ?? 'mg/dL',
      minutesSinceMeal: (data['minutesSinceMeal'] as num?)?.toInt(),
      usesHypoglycemiaRiskMedication:
          data['usesHypoglycemiaRiskMedication'] as bool? ?? false,
      hasWater: data['hasWater'] as bool? ?? false,
      hasFastCarbs: data['hasFastCarbs'] as bool? ?? false,
      completedFootCheck: data['completedFootCheck'] as bool? ?? false,
      hasConcerningSymptoms: data['hasConcerningSymptoms'] as bool? ?? false,
      notes: data['notes'] as String?,
    );
  }
}

class PostWorkoutReview {
  const PostWorkoutReview({
    this.glucoseValue,
    required this.glucoseUnit,
    required this.energyLevel,
    required this.mood,
    required this.perceivedDifficulty,
    required this.experiencedLow,
    this.notes,
  });

  final double? glucoseValue;
  final String glucoseUnit;
  final int energyLevel;
  final int mood;
  final int perceivedDifficulty;
  final bool experiencedLow;
  final String? notes;

  Map<String, dynamic> toFirestore() => {
    if (glucoseValue != null) 'glucoseValue': glucoseValue,
    'glucoseUnit': glucoseUnit,
    'energyLevel': energyLevel,
    'mood': mood,
    'perceivedDifficulty': perceivedDifficulty,
    'experiencedLow': experiencedLow,
    if (notes?.isNotEmpty ?? false) 'notes': notes,
  };

  factory PostWorkoutReview.fromFirestore(Map<String, dynamic> data) {
    return PostWorkoutReview(
      glucoseValue: (data['glucoseValue'] as num?)?.toDouble(),
      glucoseUnit: data['glucoseUnit'] as String? ?? 'mg/dL',
      energyLevel: (data['energyLevel'] as num?)?.toInt() ?? 3,
      mood: (data['mood'] as num?)?.toInt() ?? 3,
      perceivedDifficulty: (data['perceivedDifficulty'] as num?)?.toInt() ?? 3,
      experiencedLow: data['experiencedLow'] as bool? ?? false,
      notes: data['notes'] as String?,
    );
  }
}

class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.activityType,
    required this.activityName,
    required this.plannedDurationMinutes,
    required this.actualDurationSeconds,
    required this.intensity,
    required this.startedAt,
    required this.completedAt,
    required this.preWorkout,
    required this.postWorkout,
    required this.source,
    this.routineId,
    this.templateId,
    this.isPlanned = true,
    this.mealRelation,
    this.consumedCarbohydrates = false,
    this.analysisVersion = 1,
  });

  final String id;
  final WorkoutActivityType activityType;
  final String activityName;
  final int plannedDurationMinutes;
  final int actualDurationSeconds;
  final WorkoutIntensity intensity;
  final DateTime startedAt;
  final DateTime completedAt;
  final PreWorkoutCheck preWorkout;
  final PostWorkoutReview postWorkout;
  final WorkoutSource source;
  final String? routineId;
  final String? templateId;
  final bool isPlanned;
  final String? mealRelation;
  final bool consumedCarbohydrates;
  final int analysisVersion;

  Map<String, dynamic> toFirestore() => {
    'activityType': activityType.name,
    'activityName': activityName,
    'plannedDurationMinutes': plannedDurationMinutes,
    'actualDurationSeconds': actualDurationSeconds,
    'intensity': intensity.name,
    'status': 'completed',
    'startedAt': Timestamp.fromDate(startedAt),
    'completedAt': Timestamp.fromDate(completedAt),
    'preWorkout': preWorkout.toFirestore(),
    'postWorkout': postWorkout.toFirestore(),
    'source': source.name,
    if (routineId != null) 'routineId': routineId,
    if (templateId != null) 'templateId': templateId,
    'isPlanned': isPlanned,
    if (mealRelation != null) 'mealRelation': mealRelation,
    'consumedCarbohydrates': consumedCarbohydrates,
    'analysisVersion': analysisVersion,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory WorkoutSession.fromFirestore(String id, Map<String, dynamic> data) {
    final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
    final completedAt = (data['completedAt'] as Timestamp?)?.toDate();

    return WorkoutSession(
      id: id,
      activityType: _enumByName(
        WorkoutActivityType.values,
        data['activityType'],
        WorkoutActivityType.custom,
      ),
      activityName: data['activityName'] as String? ?? 'Workout',
      plannedDurationMinutes:
          (data['plannedDurationMinutes'] as num?)?.toInt() ?? 0,
      actualDurationSeconds:
          (data['actualDurationSeconds'] as num?)?.toInt() ?? 0,
      intensity: _enumByName(
        WorkoutIntensity.values,
        data['intensity'],
        WorkoutIntensity.moderate,
      ),
      startedAt: startedAt ?? DateTime.now(),
      completedAt: completedAt ?? startedAt ?? DateTime.now(),
      preWorkout: PreWorkoutCheck.fromFirestore(
        Map<String, dynamic>.from(data['preWorkout'] as Map? ?? const {}),
      ),
      postWorkout: PostWorkoutReview.fromFirestore(
        Map<String, dynamic>.from(data['postWorkout'] as Map? ?? const {}),
      ),
      source: _enumByName(
        WorkoutSource.values,
        data['source'],
        WorkoutSource.manual,
      ),
      routineId: data['routineId'] as String?,
      templateId: data['templateId'] as String?,
      isPlanned: data['isPlanned'] as bool? ?? true,
      mealRelation: data['mealRelation'] as String?,
      consumedCarbohydrates: data['consumedCarbohydrates'] as bool? ?? false,
      analysisVersion: (data['analysisVersion'] as num?)?.toInt() ?? 1,
    );
  }
}

class WorkoutDraft {
  const WorkoutDraft({
    required this.activityType,
    required this.activityName,
    required this.plannedDurationMinutes,
    required this.intensity,
    required this.preWorkout,
    this.source = WorkoutSource.manual,
    this.routineId,
    this.templateId,
    this.isPlanned = true,
    this.mealRelation,
    this.consumedCarbohydrates = false,
  });

  final WorkoutActivityType activityType;
  final String activityName;
  final int plannedDurationMinutes;
  final WorkoutIntensity intensity;
  final PreWorkoutCheck preWorkout;
  final WorkoutSource source;
  final String? routineId;
  final String? templateId;
  final bool isPlanned;
  final String? mealRelation;
  final bool consumedCarbohydrates;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

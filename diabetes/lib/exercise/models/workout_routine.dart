import 'workout_session.dart';

class WorkoutStep {
  const WorkoutStep({
    required this.name,
    required this.instruction,
    required this.durationSeconds,
    this.accessibilityAlternative,
  });

  final String name;
  final String instruction;
  final int durationSeconds;
  final String? accessibilityAlternative;
}

class WorkoutRoutine {
  const WorkoutRoutine({
    required this.id,
    required this.name,
    required this.description,
    required this.activityType,
    required this.intensity,
    required this.steps,
  });

  final String id;
  final String name;
  final String description;
  final WorkoutActivityType activityType;
  final WorkoutIntensity intensity;
  final List<WorkoutStep> steps;

  int get durationSeconds =>
      steps.fold(0, (total, step) => total + step.durationSeconds);

  int get durationMinutes => (durationSeconds / 60).ceil();
}

const builtInWorkoutRoutines = <WorkoutRoutine>[
  WorkoutRoutine(
    id: 'beginner_walk_10',
    name: '10-minute beginner walk',
    description: 'A gentle warm-up, moderate walk, and gradual cool-down.',
    activityType: WorkoutActivityType.walking,
    intensity: WorkoutIntensity.moderate,
    steps: [
      WorkoutStep(
        name: 'Easy warm-up',
        instruction: 'Walk at a comfortable pace and let your body warm up.',
        durationSeconds: 120,
      ),
      WorkoutStep(
        name: 'Moderate walk',
        instruction:
            'Increase your pace while staying comfortable enough to talk.',
        durationSeconds: 360,
      ),
      WorkoutStep(
        name: 'Cool-down',
        instruction: 'Gradually slow to an easy pace.',
        durationSeconds: 120,
      ),
    ],
  ),
  WorkoutRoutine(
    id: 'chair_mobility_10',
    name: '10-minute chair routine',
    description: 'Seated movements for mobility and light activity.',
    activityType: WorkoutActivityType.chairExercise,
    intensity: WorkoutIntensity.light,
    steps: [
      WorkoutStep(
        name: 'Seated marching',
        instruction: 'Sit tall and alternate lifting each knee comfortably.',
        durationSeconds: 120,
      ),
      WorkoutStep(
        name: 'Arm raises',
        instruction: 'Raise both arms only as high as feels comfortable.',
        durationSeconds: 90,
      ),
      WorkoutStep(
        name: 'Knee extensions',
        instruction: 'Slowly straighten one leg at a time, then lower it.',
        durationSeconds: 120,
      ),
      WorkoutStep(
        name: 'Torso rotations',
        instruction:
            'Gently rotate from side to side without forcing the range.',
        durationSeconds: 120,
      ),
      WorkoutStep(
        name: 'Ankle circles and breathing',
        instruction: 'Circle each ankle, then finish with slow breaths.',
        durationSeconds: 150,
      ),
    ],
  ),
  WorkoutRoutine(
    id: 'beginner_strength_10',
    name: '10-minute beginner strength',
    description: 'Five approachable movements using body weight or a chair.',
    activityType: WorkoutActivityType.strength,
    intensity: WorkoutIntensity.light,
    steps: [
      WorkoutStep(
        name: 'Chair squats',
        instruction:
            'Stand from a stable chair and sit back down with control.',
        durationSeconds: 120,
        accessibilityAlternative:
            'Remain seated and alternate lifting each knee.',
      ),
      WorkoutStep(
        name: 'Wall push-ups',
        instruction: 'Use a stable wall and keep your body in a straight line.',
        durationSeconds: 120,
        accessibilityAlternative:
            'Press your palms together firmly, then release.',
      ),
      WorkoutStep(
        name: 'Standing or seated rows',
        instruction:
            'Pull a resistance band toward your ribs, keeping shoulders relaxed.',
        durationSeconds: 120,
        accessibilityAlternative:
            'Without a band, squeeze your shoulder blades together and release.',
      ),
      WorkoutStep(
        name: 'Calf raises',
        instruction:
            'Hold a stable surface and slowly lift and lower your heels.',
        durationSeconds: 120,
        accessibilityAlternative: 'While seated, lift and lower both heels.',
      ),
      WorkoutStep(
        name: 'Shoulder press and cool-down',
        instruction:
            'Press light weights or empty hands overhead comfortably, then relax.',
        durationSeconds: 120,
      ),
    ],
  ),
  WorkoutRoutine(
    id: 'mobility_10',
    name: '10-minute mobility',
    description: 'Gentle stretches and balance work for everyday movement.',
    activityType: WorkoutActivityType.stretching,
    intensity: WorkoutIntensity.light,
    steps: [
      WorkoutStep(
        name: 'Shoulder circles',
        instruction: 'Make slow circles while keeping your neck relaxed.',
        durationSeconds: 90,
      ),
      WorkoutStep(
        name: 'Calf stretch',
        instruction: 'Use a wall for support and stretch one calf at a time.',
        durationSeconds: 120,
        accessibilityAlternative:
            'Sit and gently draw your toes toward you one foot at a time.',
      ),
      WorkoutStep(
        name: 'Hamstring stretch',
        instruction: 'Use a chair and keep the stretch gentle.',
        durationSeconds: 120,
      ),
      WorkoutStep(
        name: 'Gentle rotations',
        instruction:
            'Rotate your upper body slowly within a comfortable range.',
        durationSeconds: 120,
      ),
      WorkoutStep(
        name: 'Supported balance',
        instruction:
            'Stand near a stable surface and practice shifting weight.',
        durationSeconds: 90,
        accessibilityAlternative:
            'Stay seated and slowly shift your weight from side to side.',
      ),
      WorkoutStep(
        name: 'Slow breathing',
        instruction: 'Finish with comfortable, slow breaths.',
        durationSeconds: 60,
      ),
    ],
  ),
];

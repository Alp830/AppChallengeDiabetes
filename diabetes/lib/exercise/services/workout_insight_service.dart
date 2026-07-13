import '../models/workout_session.dart';

class WorkoutInsight {
  const WorkoutInsight({required this.title, required this.message});

  final String title;
  final String message;
}

class WorkoutInsightService {
  const WorkoutInsightService();

  List<WorkoutInsight> buildInsights(List<WorkoutSession> sessions) {
    if (sessions.length < 3) {
      return const [];
    }

    final insights = <WorkoutInsight>[];
    final recent = sessions.take(20).toList();
    final totalMinutes = recent.fold<int>(
      0,
      (sum, session) => sum + (session.actualDurationSeconds / 60).round(),
    );
    final averageMinutes = (totalMinutes / recent.length).round();
    insights.add(
      WorkoutInsight(
        title: 'Your recent routine',
        message:
            'Your last ${recent.length} workouts averaged $averageMinutes minutes.',
      ),
    );

    final pairedGlucose = recent
        .where(
          (session) =>
              session.preWorkout.glucoseValue != null &&
              session.postWorkout.glucoseValue != null &&
              session.preWorkout.glucoseUnit == session.postWorkout.glucoseUnit,
        )
        .toList();
    if (pairedGlucose.length >= 3) {
      final averageChange =
          pairedGlucose.fold<double>(0, (sum, session) {
            return sum +
                session.postWorkout.glucoseValue! -
                session.preWorkout.glucoseValue!;
          }) /
          pairedGlucose.length;
      final direction = averageChange.abs() < 1
          ? 'was about the same'
          : averageChange < 0
          ? 'was ${averageChange.abs().round()} ${pairedGlucose.first.preWorkout.glucoseUnit} lower'
          : 'was ${averageChange.round()} ${pairedGlucose.first.preWorkout.glucoseUnit} higher';
      insights.add(
        WorkoutInsight(
          title: 'Logged glucose pattern',
          message:
              'Across ${pairedGlucose.length} workouts with paired readings, your ending glucose $direction on average. This is an observation, not a prediction.',
        ),
      );
    }

    final lows = recent
        .where((session) => session.postWorkout.experiencedLow)
        .length;
    if (lows > 0) {
      insights.add(
        WorkoutInsight(
          title: 'Review recorded lows',
          message:
              'You recorded low-glucose symptoms after $lows recent ${lows == 1 ? 'workout' : 'workouts'}. Consider sharing these logs with your diabetes care team.',
        ),
      );
    }

    final postMealWalks = recent
        .where((session) => session.source == WorkoutSource.postMealWalk)
        .length;
    if (postMealWalks >= 3) {
      insights.add(
        WorkoutInsight(
          title: 'Post-meal walking habit',
          message:
              'You completed $postMealWalks post-meal walks in your recent history.',
        ),
      );
    }

    return insights.take(3).toList();
  }
}

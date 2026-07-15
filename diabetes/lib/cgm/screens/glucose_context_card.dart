import 'dart:math';

import 'package:flutter/material.dart';

import '../../exercise/data/exercise_repository.dart';
import '../../exercise/models/workout_session.dart';
import '../../meals/data/meal_repository.dart';
import '../../meals/models/meal_models.dart';
import '../data/glucose_repository.dart';
import '../models/glucose_models.dart';

class GlucoseContextCard extends StatefulWidget {
  const GlucoseContextCard({
    super.key,
    required this.userId,
    required this.onLogMeal,
    required this.onOpenExercise,
    required this.onImport,
  });

  final String userId;
  final VoidCallback onLogMeal;
  final VoidCallback onOpenExercise;
  final VoidCallback onImport;

  @override
  State<GlucoseContextCard> createState() => _GlucoseContextCardState();
}

class _GlucoseContextCardState extends State<GlucoseContextCard> {
  final _glucose = GlucoseRepository();
  final _meals = MealRepository();
  final _exercise = ExerciseRepository();
  DateTime _day = DateTime.now();
  final Set<String> _dismissedReviews = {};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GlucoseSettings>(
      stream: _glucose.watchSettings(widget.userId),
      builder: (context, settingsSnapshot) {
        final settings = settingsSnapshot.data ?? const GlucoseSettings();
        return StreamBuilder<List<GlucoseReading>>(
          stream: _glucose.watchDay(widget.userId, _day),
          builder: (context, glucoseSnapshot) {
            if (glucoseSnapshot.hasError) {
              return const _ContextMessage(
                icon: Icons.cloud_off,
                message: 'Could not load glucose context. Check your connection and try again.',
              );
            }
            if (!glucoseSnapshot.hasData) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            return StreamBuilder<List<MealEvent>>(
              stream: _meals.watchMeals(widget.userId),
              builder: (context, mealSnapshot) => StreamBuilder<List<WorkoutSession>>(
                stream: _exercise.watchSessionsForDay(widget.userId, _day),
                builder: (context, workoutSnapshot) {
                  final meals = (mealSnapshot.data ?? const <MealEvent>[])
                      .where((meal) => _sameDay(meal.timestamp, _day))
                      .toList();
                  return _GlucoseCardBody(
                    day: _day,
                    readings: glucoseSnapshot.data!,
                    meals: meals,
                    workouts: workoutSnapshot.data ?? const [],
                    settings: settings,
                    onPrevious: () => setState(
                      () => _day = DateTime(_day.year, _day.month, _day.day - 1),
                    ),
                    onNext: _sameDay(_day, DateTime.now())
                        ? null
                        : () => setState(
                            () => _day = DateTime(_day.year, _day.month, _day.day + 1),
                          ),
                    onLogMeal: widget.onLogMeal,
                    onOpenExercise: widget.onOpenExercise,
                    onImport: widget.onImport,
                    reviewDismissed: _dismissedReviews.contains(_dateLabel(_day)),
                    onDismissReview: () => setState(
                      () => _dismissedReviews.add(_dateLabel(_day)),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _GlucoseCardBody extends StatelessWidget {
  const _GlucoseCardBody({
    required this.day,
    required this.readings,
    required this.meals,
    required this.workouts,
    required this.settings,
    required this.onPrevious,
    required this.onNext,
    required this.onLogMeal,
    required this.onOpenExercise,
    required this.onImport,
    required this.reviewDismissed,
    required this.onDismissReview,
  });

  final DateTime day;
  final List<GlucoseReading> readings;
  final List<MealEvent> meals;
  final List<WorkoutSession> workouts;
  final GlucoseSettings settings;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onLogMeal;
  final VoidCallback onOpenExercise;
  final VoidCallback onImport;
  final bool reviewDismissed;
  final VoidCallback onDismissReview;

  @override
  Widget build(BuildContext context) {
    final latest = readings.isEmpty ? null : readings.last;
    final isDemo = latest?.source == GlucoseSource.demo;
    final unexplainedChanges = _unexplainedChanges(readings, meals, workouts);
    return Card(
      key: const Key('glucoseContextCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Glucose context', style: Theme.of(context).textTheme.titleLarge),
                ),
                if (isDemo) const Chip(label: Text('Demo')),
              ],
            ),
            const Text('Historical imported data—not a live alarm source.'),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(onPressed: onPrevious, tooltip: 'Previous day', icon: const Icon(Icons.chevron_left)),
                Expanded(child: Text(_dateLabel(day), textAlign: TextAlign.center)),
                IconButton(onPressed: onNext, tooltip: 'Next day', icon: const Icon(Icons.chevron_right)),
              ],
            ),
            if (latest == null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No glucose readings for this day.')),
              ),
              Center(child: FilledButton.icon(onPressed: onImport, icon: const Icon(Icons.upload_file), label: const Text('Import LibreView data'))),
            ] else ...[
              Text(
                '${glucoseForDisplay(latest.valueMgDl, settings.displayUnit).toStringAsFixed(settings.displayUnit == 'mmol/L' ? 1 : 0)} ${settings.displayUnit}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text('Most recent: ${_time(latest.timestamp)}'),
              const SizedBox(height: 12),
              Semantics(
                label: _chartSummary(readings, meals, workouts, settings),
                child: SizedBox(
                  height: 190,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _GlucoseTimelinePainter(
                      readings: readings,
                      meals: meals,
                      workouts: workouts,
                      settings: settings,
                      day: day,
                      colors: Theme.of(context).colorScheme,
                    ),
                  ),
                ),
              ),
              const Row(
                children: [
                  Icon(Icons.circle, size: 12, color: Colors.orange),
                  SizedBox(width: 4),
                  Text('Meal'),
                  SizedBox(width: 16),
                  Icon(Icons.horizontal_rule, color: Colors.purple),
                  SizedBox(width: 4),
                  Text('Workout'),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (unexplainedChanges > 0 && !reviewDismissed) ...[
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Missing context review', style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        '$unexplainedChanges meaningful recorded change${unexplainedChanges == 1 ? '' : 's'} had no nearby meal or workout. Did you miss a log?',
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: onDismissReview, child: const Text('Dismiss')),
                          TextButton(onPressed: onLogMeal, child: const Text('Log meal')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: onLogMeal, icon: const Icon(Icons.restaurant), label: const Text('Log meal')),
                OutlinedButton.icon(onPressed: onOpenExercise, icon: const Icon(Icons.directions_run), label: const Text('Exercise')),
                TextButton.icon(onPressed: onImport, icon: const Icon(Icons.upload_file), label: const Text('Import')),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Continue using the official Libre app for alarms and treatment decisions.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlucoseTimelinePainter extends CustomPainter {
  _GlucoseTimelinePainter({
    required this.readings,
    required this.meals,
    required this.workouts,
    required this.settings,
    required this.day,
    required this.colors,
  });
  final List<GlucoseReading> readings;
  final List<MealEvent> meals;
  final List<WorkoutSession> workouts;
  final GlucoseSettings settings;
  final DateTime day;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0;
    const top = 12.0;
    final chart = Rect.fromLTWH(left, top, size.width - left * 2, size.height - 34);
    final values = readings.map((reading) => reading.valueMgDl).toList();
    var minimum = min(values.reduce(min), settings.rangeConfirmed ? settings.lowMgDl : 70) - 20;
    var maximum = max(values.reduce(max), settings.rangeConfirmed ? settings.highMgDl : 180) + 20;
    if (maximum - minimum < 60) maximum = minimum + 60;
    double x(DateTime time) => chart.left +
        (time.difference(DateTime(day.year, day.month, day.day)).inSeconds / 86400).clamp(0, 1) * chart.width;
    double y(double value) => chart.bottom - ((value - minimum) / (maximum - minimum)).clamp(0, 1) * chart.height;

    if (settings.rangeConfirmed) {
      canvas.drawRect(
        Rect.fromLTRB(chart.left, y(settings.highMgDl), chart.right, y(settings.lowMgDl)),
        Paint()..color = colors.primaryContainer.withValues(alpha: .45),
      );
    }
    final grid = Paint()..color = colors.outlineVariant;
    for (var hour = 0; hour <= 24; hour += 6) {
      final position = chart.left + chart.width * hour / 24;
      canvas.drawLine(Offset(position, chart.top), Offset(position, chart.bottom), grid);
    }
    final path = Path();
    for (var index = 0; index < readings.length; index++) {
      final point = Offset(x(readings[index].timestamp), y(readings[index].valueMgDl));
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, Paint()..color = colors.primary..strokeWidth = 2.5..style = PaintingStyle.stroke);
    for (final meal in meals) {
      canvas.drawCircle(Offset(x(meal.timestamp), chart.top + 7), 5, Paint()..color = Colors.orange);
    }
    for (final workout in workouts) {
      canvas.drawLine(
        Offset(x(workout.startedAt), chart.top + 18),
        Offset(x(workout.completedAt), chart.top + 18),
        Paint()..color = Colors.purple..strokeWidth = 5..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlucoseTimelinePainter oldDelegate) => true;
}

class _ContextMessage extends StatelessWidget {
  const _ContextMessage({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [Icon(icon), const SizedBox(height: 8), Text(message, textAlign: TextAlign.center)]),
    ),
  );
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
String _dateLabel(DateTime day) => '${day.month}/${day.day}/${day.year}';
String _time(DateTime date) => '${date.hour == 0 ? 12 : date.hour > 12 ? date.hour - 12 : date.hour}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
String _chartSummary(List<GlucoseReading> readings, List<MealEvent> meals, List<WorkoutSession> workouts, GlucoseSettings settings) {
  final minimum = readings.map((item) => item.valueMgDl).reduce(min);
  final maximum = readings.map((item) => item.valueMgDl).reduce(max);
  return 'Daily glucose timeline with ${readings.length} readings, ${meals.length} meal markers, and ${workouts.length} workouts. Recorded range ${glucoseForDisplay(minimum, settings.displayUnit).round()} to ${glucoseForDisplay(maximum, settings.displayUnit).round()} ${settings.displayUnit}.';
}

int _unexplainedChanges(
  List<GlucoseReading> readings,
  List<MealEvent> meals,
  List<WorkoutSession> workouts,
) {
  var count = 0;
  for (var index = 1; index < readings.length; index++) {
    final current = readings[index];
    final previous = readings[index - 1];
    if (current.timestamp.difference(previous.timestamp) > const Duration(minutes: 30) ||
        (current.valueMgDl - previous.valueMgDl).abs() < 40) {
      continue;
    }
    final hasMeal = meals.any(
      (meal) => meal.timestamp.difference(current.timestamp).abs() <= const Duration(hours: 2),
    );
    final hasWorkout = workouts.any(
      (workout) =>
          current.timestamp.isAfter(workout.startedAt.subtract(const Duration(hours: 1))) &&
          current.timestamp.isBefore(workout.completedAt.add(const Duration(hours: 2))),
    );
    if (!hasMeal && !hasWorkout) count++;
  }
  return count;
}

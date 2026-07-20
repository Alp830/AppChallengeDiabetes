import 'package:flutter/material.dart';

import '../../app_features.dart';
import '../../cgm/data/glucose_repository.dart';
import '../data/exercise_repository.dart';
import '../models/workout_session.dart';
import '../services/movement_analysis_service.dart';

class MovementLabPage extends StatefulWidget {
  const MovementLabPage({
    super.key,
    required this.userId,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
    this.exerciseRepositoryFactory,
    this.glucoseRepositoryFactory,
  });

  final String userId;
  final bool diabetesEnabled;
  final ExerciseRepository Function()? exerciseRepositoryFactory;
  final GlucoseRepository Function()? glucoseRepositoryFactory;

  @override
  State<MovementLabPage> createState() => _MovementLabPageState();
}

class _MovementLabPageState extends State<MovementLabPage> {
  late final ExerciseRepository? _exercise;
  late final GlucoseRepository? _glucose;

  @override
  void initState() {
    super.initState();
    _exercise = widget.diabetesEnabled
        ? (widget.exerciseRepositoryFactory?.call() ?? ExerciseRepository())
        : null;
    _glucose = widget.diabetesEnabled
        ? (widget.glucoseRepositoryFactory?.call() ?? GlucoseRepository())
        : null;
  }

  Future<List<WorkoutResponse>> _analyze(List<WorkoutSession> sessions) async {
    if (sessions.isEmpty) return const [];
    final glucose = _glucose;
    if (glucose == null) return const [];
    final oldest = sessions
        .map((item) => item.startedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final newest = sessions
        .map((item) => item.completedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final readings = await glucose.getRange(
      widget.userId,
      oldest.subtract(const Duration(minutes: 15)),
      newest.add(const Duration(days: 1, hours: 6)),
    );
    return sessions
        .map(
          (session) =>
              const MovementAnalysisService().response(session, readings),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _exercise;
    final glucose = _glucose;
    if (exercise == null || glucose == null) {
      return const SizedBox.shrink(key: Key('diabetesFeatureDisabled'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Movement Lab')),
      body: StreamBuilder<List<WorkoutSession>>(
        stream: exercise.watchRecentSessions(widget.userId, limit: 100),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Could not load movement history.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder<List<WorkoutResponse>>(
            future: _analyze(snapshot.data!),
            builder: (context, responseSnapshot) {
              if (!responseSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return StreamBuilder<bool>(
                stream: glucose.watchHasGlucoseData(widget.userId),
                builder: (context, glucoseSnapshot) => _MovementLabView(
                  responses: responseSnapshot.data!,
                  hasGlucose: glucoseSnapshot.data ?? false,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MovementLabView extends StatelessWidget {
  const _MovementLabView({required this.responses, required this.hasGlucose});
  final List<WorkoutResponse> responses;

  /// Movement Lab is entirely a glucose x exercise view, so its sections only
  /// appear once the user has imported glucose data.
  final bool hasGlucose;

  @override
  Widget build(BuildContext context) {
    final grouped = <WorkoutActivityType, List<WorkoutResponse>>{};
    for (final response in responses) {
      grouped
          .putIfAbsent(response.session.activityType, () => [])
          .add(response);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Movement Lab describes your recorded glucose context. It cannot tell you whether it is safe to exercise or recommend carbohydrates.',
            ),
          ),
        ),
        if (!hasGlucose)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Import your glucose data to see how your workouts affect your glucose.',
            ),
          )
        else ...[
          Text(
            'Exercise Type Profiles',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (responses.isEmpty)
            const Text(
              'Complete workouts and import glucose data to build profiles.',
            )
          else
            for (final entry in grouped.entries)
              _MovementProfile(type: entry.key, responses: entry.value),
          const SizedBox(height: 20),
          Text(
            'Movement comparisons',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          for (final feature in const [
            'Movement Timing Comparison',
            'During-and-After View',
            'Post-Meal Movement Comparison',
            'Intensity Signature',
            'Workout Repeatability',
            'Movement Break History',
            'Workout Memory',
            'Planned Versus Unplanned Activity',
            'Late/Overnight Pattern',
          ])
            Card(
              child: ListTile(
                title: Text(feature),
                subtitle: Text(_movementSummary(feature, responses)),
                trailing: Icon(
                  responses.where((item) => item.hasCoverage).length >= 3
                      ? Icons.check_circle_outline
                      : Icons.hourglass_empty,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _MovementProfile extends StatelessWidget {
  const _MovementProfile({required this.type, required this.responses});
  final WorkoutActivityType type;
  final List<WorkoutResponse> responses;

  @override
  Widget build(BuildContext context) {
    final covered = responses.where((item) => item.hasCoverage).toList();
    final changes = covered
        .map((item) => item.duringChange)
        .whereType<double>()
        .toList();
    final after = covered
        .map((item) => item.twoHourChange)
        .whereType<double>()
        .toList();
    final averageDuring = changes.isEmpty
        ? null
        : changes.reduce((a, b) => a + b) / changes.length;
    final averageAfter = after.isEmpty
        ? null
        : after.reduce((a, b) => a + b) / after.length;
    final planned = responses.where((item) => item.session.isPlanned).length;
    return Card(
      child: ExpansionTile(
        title: Text(_activityName(type)),
        subtitle: Text(
          '${const MovementAnalysisService().evidenceLevel(covered.length)} • ${covered.length} supported events',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (averageDuring == null)
            const Text('More imported glucose coverage is needed.')
          else ...[
            Text(
              'During similar workouts, ending glucose was associated with an average change of ${averageDuring.round()} mg/dL.',
            ),
            if (averageAfter != null)
              Text(
                'Two hours afterward, the recorded average change was ${averageAfter.round()} mg/dL.',
              ),
            Text(
              '$planned planned and ${responses.length - planned} unplanned recorded activities.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Why am I seeing this? Baseline uses readings from the 15 minutes before each workout. This is an observation, not a prediction.',
            ),
          ],
        ],
      ),
    );
  }
}

String _activityName(WorkoutActivityType type) {
  final spaced = type.name.replaceAllMapped(
    RegExp(r'([A-Z])'),
    (match) => ' ${match.group(1)!.toLowerCase()}',
  );
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

String _movementSummary(String feature, List<WorkoutResponse> responses) {
  final covered = responses.where((item) => item.hasCoverage).toList();
  if (covered.length < 3) {
    return 'At least three workouts with CGM coverage are needed.';
  }
  return switch (feature) {
    'Movement Timing Comparison' =>
      '${covered.map((item) => item.session.mealRelation ?? 'No meal timing').toSet().length} meal-timing contexts recorded.',
    'During-and-After View' =>
      '${covered.where((item) => item.twoHourMgDl != null).length} workouts include two-hour follow-up coverage.',
    'Post-Meal Movement Comparison' =>
      '${covered.where((item) => item.session.mealRelation != null).length} workouts include meal timing.',
    'Intensity Signature' =>
      '${covered.map((item) => item.session.intensity).toSet().length} intensity levels have supported records.',
    'Workout Repeatability' =>
      '${covered.map((item) => item.session.activityType).toSet().length} activity profiles are available.',
    'Movement Break History' =>
      '${responses.where((item) => item.session.activityType == WorkoutActivityType.movementBreak).length} movement breaks recorded.',
    'Workout Memory' =>
      '${covered.length} supported past responses are available before a repeated workout.',
    'Planned Versus Unplanned Activity' =>
      '${covered.where((item) => item.session.isPlanned).length} planned and ${covered.where((item) => !item.session.isPlanned).length} unplanned supported activities.',
    'Late/Overnight Pattern' =>
      '${covered.where((item) => item.overnightAverageMgDl != null).length} evening workouts include overnight coverage.',
    _ => 'Based on recorded events; open profiles to review supporting data.',
  };
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_features.dart';
import '../../navigation/app_feature_navigation.dart';
import '../data/exercise_repository.dart';
import '../models/exercise_profile.dart';
import '../models/workout_routine.dart';
import '../models/workout_session.dart';
import '../services/exercise_safety_service.dart';
import '../services/workout_insight_service.dart';
import 'movement_lab_page.dart';

class ExercisePage extends StatefulWidget {
  const ExercisePage({
    super.key,
    required this.userId,
    this.repository,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
  });

  final String userId;
  final ExerciseRepository? repository;
  final bool diabetesEnabled;

  @override
  State<ExercisePage> createState() => _ExercisePageState();
}

class _ExercisePageState extends State<ExercisePage> {
  late final ExerciseRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ExerciseRepository();
  }

  Future<void> _startWorkout({
    WorkoutActivityType? initialActivity,
    WorkoutRoutine? routine,
    WorkoutSource source = WorkoutSource.manual,
  }) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => WorkoutSetupPage(
          userId: widget.userId,
          repository: _repository,
          initialActivity: initialActivity,
          routine: routine,
          source: source,
          diabetesEnabled: widget.diabetesEnabled,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WorkoutSession>>(
      stream: _repository.watchRecentSessions(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ExerciseError(
            message: 'Could not load workouts: ${snapshot.error}',
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final sessions = snapshot.data!;
        final weekStart = _startOfWeek(DateTime.now());
        final weeklySessions = sessions
            .where((session) => !session.startedAt.isBefore(weekStart))
            .toList();
        final weeklyMinutes = weeklySessions.fold<int>(
          0,
          (sum, session) => sum + (session.actualDurationSeconds / 60).round(),
        );
        final strengthSessions = weeklySessions
            .where(
              (session) => session.activityType == WorkoutActivityType.strength,
            )
            .length;
        final insights = const WorkoutInsightService().buildInsights(
          sessions,
          diabetesEnabled: widget.diabetesEnabled,
        );

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _ProfileProgressCard(
              userId: widget.userId,
              repository: _repository,
              activeMinutes: weeklyMinutes,
              strengthSessions: strengthSessions,
              diabetesEnabled: widget.diabetesEnabled,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('startWorkoutButton'),
              onPressed: _startWorkout,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start a workout'),
            ),
            const SizedBox(height: 8),
            if (widget.diabetesEnabled)
              OutlinedButton.icon(
                onPressed: () => AppFeatureNavigation.pushDiabetesPage<void>(
                  context,
                  diabetesEnabled: widget.diabetesEnabled,
                  builder: (context) => MovementLabPage(
                    userId: widget.userId,
                    diabetesEnabled: widget.diabetesEnabled,
                  ),
                ),
                icon: const Icon(Icons.query_stats),
                label: const Text('Open Movement Lab'),
              ),
            const SizedBox(height: 24),
            Text('Quick start', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickStartCard(
                  icon: Icons.directions_walk,
                  title: '10-minute walk',
                  onTap: () => _startWorkout(
                    initialActivity: WorkoutActivityType.walking,
                  ),
                ),
                _QuickStartCard(
                  icon: Icons.fitness_center,
                  title: 'Strength',
                  onTap: () => _startWorkout(
                    initialActivity: WorkoutActivityType.strength,
                  ),
                ),
                _QuickStartCard(
                  icon: Icons.accessible_forward,
                  title: 'Chair exercise',
                  onTap: () => _startWorkout(
                    initialActivity: WorkoutActivityType.chairExercise,
                  ),
                ),
                _QuickStartCard(
                  icon: Icons.self_improvement,
                  title: 'Stretching',
                  onTap: () => _startWorkout(
                    initialActivity: WorkoutActivityType.stretching,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Guided routines',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final routine in builtInWorkoutRoutines)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(routine.activityType.icon)),
                  title: Text(routine.name),
                  subtitle: Text(routine.description),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _startWorkout(routine: routine),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _startWorkout(
                initialActivity: WorkoutActivityType.walking,
                source: WorkoutSource.postMealWalk,
              ),
              icon: const Icon(Icons.restaurant),
              label: const Text('Start a post-meal walk'),
            ),
            if (insights.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Your patterns',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final insight in insights)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.insights),
                    title: Text(insight.title),
                    subtitle: Text(insight.message),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent workouts',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (sessions.isNotEmpty)
                  TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (context) => WorkoutHistoryPage(
                          userId: widget.userId,
                          repository: _repository,
                          diabetesEnabled: widget.diabetesEnabled,
                        ),
                      ),
                    ),
                    child: const Text('View all'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (sessions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.directions_run, size: 48),
                      SizedBox(height: 12),
                      Text(
                        'No workouts yet',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Start with an activity that feels manageable today.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final session in sessions.take(3))
                WorkoutSessionTile(
                  session: session,
                  diabetesEnabled: widget.diabetesEnabled,
                ),
          ],
        );
      },
    );
  }
}

class WorkoutSetupPage extends StatefulWidget {
  const WorkoutSetupPage({
    super.key,
    required this.userId,
    required this.repository,
    this.initialActivity,
    this.routine,
    this.source = WorkoutSource.manual,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
  });

  final String userId;
  final ExerciseRepository repository;
  final WorkoutActivityType? initialActivity;
  final WorkoutRoutine? routine;
  final WorkoutSource source;
  final bool diabetesEnabled;

  @override
  State<WorkoutSetupPage> createState() => _WorkoutSetupPageState();
}

class _WorkoutSetupPageState extends State<WorkoutSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _glucoseController = TextEditingController();
  final _mealMinutesController = TextEditingController();
  final _customActivityController = TextEditingController();
  final _notesController = TextEditingController();

  late WorkoutActivityType _activity;
  WorkoutIntensity _intensity = WorkoutIntensity.moderate;
  int _durationMinutes = 10;
  bool _usesRiskMedication = false;
  bool _hasWater = true;
  bool _hasFastCarbs = false;
  bool _completedFootCheck = false;
  bool _hasConcerningSymptoms = false;
  bool _isPlanned = true;
  bool _consumedCarbohydrates = false;
  String _glucoseUnit = 'mg/dL';

  @override
  void initState() {
    super.initState();
    _activity =
        widget.routine?.activityType ??
        widget.initialActivity ??
        WorkoutActivityType.walking;
    if (widget.routine != null) {
      _durationMinutes = widget.routine!.durationMinutes;
      _intensity = widget.routine!.intensity;
    } else if (widget.source == WorkoutSource.postMealWalk) {
      _durationMinutes = 10;
      _intensity = WorkoutIntensity.light;
    }
    if (widget.diabetesEnabled) _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.repository.getProfile(widget.userId);
      if (mounted) {
        setState(() => _glucoseUnit = profile.glucoseUnit);
      }
    } catch (_) {
      // Keep the default unit when profile settings are unavailable.
    }
  }

  @override
  void dispose() {
    _glucoseController.dispose();
    _mealMinutesController.dispose();
    _customActivityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final check = PreWorkoutCheck(
      glucoseValue: widget.diabetesEnabled
          ? _optionalDouble(_glucoseController.text)
          : null,
      glucoseUnit: _glucoseUnit,
      minutesSinceMeal: _optionalInt(_mealMinutesController.text),
      usesHypoglycemiaRiskMedication:
          widget.diabetesEnabled && _usesRiskMedication,
      hasWater: _hasWater,
      hasFastCarbs: widget.diabetesEnabled && _hasFastCarbs,
      completedFootCheck: !widget.diabetesEnabled || _completedFootCheck,
      hasConcerningSymptoms: _hasConcerningSymptoms,
      notes: _notesController.text.trim(),
    );
    final safety = const ExerciseSafetyService().evaluate(
      check,
      diabetesEnabled: widget.diabetesEnabled,
    );
    final shouldStart = await _showSafetyDialog(safety);
    if (!shouldStart || !mounted) {
      return;
    }

    final activityName =
        widget.routine?.name ??
        (_activity == WorkoutActivityType.custom
            ? _customActivityController.text.trim()
            : widget.source == WorkoutSource.postMealWalk
            ? 'Post-meal walk'
            : _activity.label);
    final draft = WorkoutDraft(
      activityType: _activity,
      activityName: activityName,
      plannedDurationMinutes: _durationMinutes,
      intensity: _intensity,
      preWorkout: check,
      source: widget.routine != null
          ? WorkoutSource.guidedRoutine
          : widget.source,
      routineId: widget.routine?.id,
      templateId: widget.routine?.id,
      isPlanned: _isPlanned,
      mealRelation: _mealRelation(_optionalInt(_mealMinutesController.text)),
      consumedCarbohydrates: _consumedCarbohydrates,
    );
    final result = await Navigator.of(context).push<ActiveWorkoutResult>(
      MaterialPageRoute(
        builder: (context) =>
            ActiveWorkoutPage(draft: draft, routine: widget.routine),
      ),
    );
    if (result == null || !mounted) {
      return;
    }

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => WorkoutReviewPage(
          userId: widget.userId,
          repository: widget.repository,
          draft: draft,
          result: result,
          diabetesEnabled: widget.diabetesEnabled,
        ),
      ),
    );
    if (saved == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<bool> _showSafetyDialog(SafetyResult result) async {
    final colorScheme = Theme.of(context).colorScheme;
    final isBlocked = result.severity == SafetySeverity.stop;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          isBlocked ? Icons.report_gmailerrorred : Icons.health_and_safety,
          color: isBlocked ? colorScheme.error : colorScheme.primary,
          size: 40,
        ),
        title: Text(isBlocked ? 'Do not start yet' : 'Before you start'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final message in result.messages)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('• $message'),
              ),
            const SizedBox(height: 4),
            if (widget.diabetesEnabled)
              const Text(
                'This checklist does not replace instructions from your diabetes care team.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(isBlocked ? 'Close' : 'Go back'),
          ),
          if (!isBlocked)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Start workout'),
            ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan workout')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.routine != null) ...[
              Card(
                child: ListTile(
                  leading: Icon(widget.routine!.activityType.icon),
                  title: Text(widget.routine!.name),
                  subtitle: Text(widget.routine!.description),
                ),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<WorkoutActivityType>(
              initialValue: _activity,
              decoration: InputDecoration(labelText: 'Activity'),
              items: [
                for (final activity in WorkoutActivityType.values)
                  DropdownMenuItem(
                    value: activity,
                    child: Text(activity.label),
                  ),
              ],
              onChanged: widget.routine != null
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _activity = value);
                      }
                    },
            ),
            if (_activity == WorkoutActivityType.custom) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _customActivityController,
                maxLength: 60,
                decoration: InputDecoration(labelText: 'Activity name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter an activity name'
                    : null,
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Duration: $_durationMinutes minutes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: _durationMinutes.toDouble(),
              min: 5,
              max: 90,
              divisions: 17,
              label: '$_durationMinutes minutes',
              onChanged: widget.routine != null
                  ? null
                  : (value) {
                      setState(() => _durationMinutes = value.round());
                    },
            ),
            const SizedBox(height: 8),
            Text('Intensity', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<WorkoutIntensity>(
              segments: [
                for (final intensity in WorkoutIntensity.values)
                  ButtonSegment(value: intensity, label: Text(intensity.label)),
              ],
              selected: {_intensity},
              onSelectionChanged: widget.routine != null
                  ? null
                  : (selection) {
                      setState(() => _intensity = selection.first);
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('This activity was planned'),
              subtitle: const Text(
                'Turn off for errands, chores, or unexpected activity.',
              ),
              value: _isPlanned,
              onChanged: (value) => setState(() => _isPlanned = value),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I consumed carbohydrates for this activity'),
              value: _consumedCarbohydrates,
              onChanged: (value) =>
                  setState(() => _consumedCarbohydrates = value ?? false),
            ),
            const SizedBox(height: 28),
            Text(
              'Pre-workout check',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            if (widget.diabetesEnabled) ...[
              const Text(
                'Glucose is optional. Use the targets and exercise plan provided by your care team.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _glucoseController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Current glucose (optional)',
                  suffixText: _glucoseUnit,
                ),
                validator: _validateOptionalPositiveNumber,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _mealMinutesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minutes since last meal (optional)',
              ),
              validator: _validateOptionalPositiveNumber,
            ),
            const SizedBox(height: 8),
            if (widget.diabetesEnabled)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'I use insulin or medication that can cause lows',
                ),
                subtitle: const Text('Ask your care team if you are unsure.'),
                value: _usesRiskMedication,
                onChanged: (value) {
                  setState(() => _usesRiskMedication = value);
                },
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I have water available'),
              value: _hasWater,
              onChanged: (value) {
                setState(() => _hasWater = value ?? false);
              },
            ),
            if (widget.diabetesEnabled)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I have fast-acting carbohydrates available'),
                value: _hasFastCarbs,
                onChanged: (value) {
                  setState(() => _hasFastCarbs = value ?? false);
                },
              ),
            if (widget.diabetesEnabled)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I checked my footwear and feet'),
                value: _completedFootCheck,
                onChanged: (value) {
                  setState(() => _completedFootCheck = value ?? false);
                },
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I have concerning symptoms right now'),
              subtitle: const Text(
                'For example: chest pain, severe dizziness, confusion, or unusual weakness.',
              ),
              value: _hasConcerningSymptoms,
              onChanged: (value) {
                setState(() => _hasConcerningSymptoms = value);
              },
            ),
            TextFormField(
              controller: _notesController,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _continue,
              icon: const Icon(Icons.health_and_safety),
              label: const Text('Review and start'),
            ),
          ],
        ),
      ),
    );
  }
}

class ActiveWorkoutResult {
  const ActiveWorkoutResult({
    required this.startedAt,
    required this.completedAt,
    required this.actualDurationSeconds,
  });

  final DateTime startedAt;
  final DateTime completedAt;
  final int actualDurationSeconds;
}

class ActiveWorkoutPage extends StatefulWidget {
  const ActiveWorkoutPage({super.key, required this.draft, this.routine});

  final WorkoutDraft draft;
  final WorkoutRoutine? routine;

  @override
  State<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends State<ActiveWorkoutPage>
    with WidgetsBindingObserver {
  late final DateTime _startedAt;
  Timer? _ticker;
  DateTime? _pausedAt;
  Duration _totalPaused = Duration.zero;
  bool _goalMessageShown = false;

  bool get _isPaused => _pausedAt != null;

  Duration get _elapsed {
    final end = _pausedAt ?? DateTime.now();
    final elapsed = end.difference(_startedAt) - _totalPaused;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _isPaused) {
        return;
      }
      setState(() {});
      final target = Duration(minutes: widget.draft.plannedDurationMinutes);
      if (!_goalMessageShown && _elapsed >= target) {
        _goalMessageShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You reached your planned workout time.'),
          ),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  void _togglePause() {
    setState(() {
      if (_pausedAt == null) {
        _pausedAt = DateTime.now();
      } else {
        _totalPaused += DateTime.now().difference(_pausedAt!);
        _pausedAt = null;
      }
    });
  }

  void _finish() {
    final completedAt = DateTime.now();
    Navigator.of(context).pop(
      ActiveWorkoutResult(
        startedAt: _startedAt,
        completedAt: completedAt,
        actualDurationSeconds: _elapsed.inSeconds,
      ),
    );
  }

  Future<bool> _confirmExit() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this workout?'),
        content: const Text('This active workout has not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep working out'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _elapsed;
    final targetSeconds = widget.draft.plannedDurationMinutes * 60;
    final progress = targetSeconds == 0
        ? 0.0
        : (elapsed.inSeconds / targetSeconds).clamp(0.0, 1.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await _confirmExit() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.draft.activityName)),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    Icon(widget.draft.activityType.icon, size: 72),
                    const SizedBox(height: 24),
                    Semantics(
                      label: 'Elapsed workout time ${_formatDuration(elapsed)}',
                      child: Text(
                        _formatDuration(elapsed),
                        style: Theme.of(context).textTheme.displayLarge,
                      ),
                    ),
                    Text(
                      _isPaused
                          ? 'Paused'
                          : 'Goal: ${widget.draft.plannedDurationMinutes} minutes',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 20),
                    LinearProgressIndicator(value: progress),
                    if (widget.routine != null) ...[
                      const SizedBox(height: 24),
                      _GuidedStepCard(
                        routine: widget.routine!,
                        elapsed: elapsed,
                      ),
                    ],
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _togglePause,
                          icon: Icon(
                            _isPaused ? Icons.play_arrow : Icons.pause,
                          ),
                          label: Text(_isPaused ? 'Resume' : 'Pause'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _finish,
                          icon: const Icon(Icons.stop),
                          label: const Text('Finish'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Stop exercising if you feel unwell. Follow your personal care plan or seek emergency help for severe symptoms.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WorkoutReviewPage extends StatefulWidget {
  const WorkoutReviewPage({
    super.key,
    required this.userId,
    required this.repository,
    required this.draft,
    required this.result,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
  });

  final String userId;
  final ExerciseRepository repository;
  final WorkoutDraft draft;
  final ActiveWorkoutResult result;
  final bool diabetesEnabled;

  @override
  State<WorkoutReviewPage> createState() => _WorkoutReviewPageState();
}

class _WorkoutReviewPageState extends State<WorkoutReviewPage> {
  final _formKey = GlobalKey<FormState>();
  final _glucoseController = TextEditingController();
  final _notesController = TextEditingController();
  double _energy = 3;
  double _mood = 3;
  double _difficulty = 3;
  bool _experiencedLow = false;
  bool _saving = false;

  @override
  void dispose() {
    _glucoseController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    try {
      final review = PostWorkoutReview(
        glucoseValue: widget.diabetesEnabled
            ? _optionalDouble(_glucoseController.text)
            : null,
        glucoseUnit: widget.draft.preWorkout.glucoseUnit,
        energyLevel: _energy.round(),
        mood: _mood.round(),
        perceivedDifficulty: _difficulty.round(),
        experiencedLow: widget.diabetesEnabled && _experiencedLow,
        notes: _notesController.text.trim(),
      );
      final session = WorkoutSession(
        id: '',
        activityType: widget.draft.activityType,
        activityName: widget.draft.activityName,
        plannedDurationMinutes: widget.draft.plannedDurationMinutes,
        actualDurationSeconds: widget.result.actualDurationSeconds,
        intensity: widget.draft.intensity,
        startedAt: widget.result.startedAt,
        completedAt: widget.result.completedAt,
        preWorkout: widget.draft.preWorkout,
        postWorkout: review,
        source: widget.draft.source,
        routineId: widget.draft.routineId,
        templateId: widget.draft.templateId,
        isPlanned: widget.draft.isPlanned,
        mealRelation: widget.draft.mealRelation,
        consumedCarbohydrates: widget.draft.consumedCarbohydrates,
      );
      await widget.repository.saveCompletedSession(widget.userId, session);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save workout: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Workout review')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(widget.draft.activityType.icon),
                  title: Text(widget.draft.activityName),
                  subtitle: Text(
                    '${_formatDuration(Duration(seconds: widget.result.actualDurationSeconds))} • ${widget.draft.intensity.label}',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.diabetesEnabled)
                TextFormField(
                  controller: _glucoseController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Ending glucose (optional)',
                    suffixText: widget.draft.preWorkout.glucoseUnit,
                  ),
                  validator: _validateOptionalPositiveNumber,
                ),
              const SizedBox(height: 20),
              _RatingSlider(
                label: 'Energy',
                lowLabel: 'Low',
                highLabel: 'High',
                value: _energy,
                onChanged: (value) => setState(() => _energy = value),
              ),
              _RatingSlider(
                label: 'Mood',
                lowLabel: 'Low',
                highLabel: 'Great',
                value: _mood,
                onChanged: (value) => setState(() => _mood = value),
              ),
              _RatingSlider(
                label: 'Difficulty',
                lowLabel: 'Easy',
                highLabel: 'Very hard',
                value: _difficulty,
                onChanged: (value) => setState(() => _difficulty = value),
              ),
              if (widget.diabetesEnabled)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('I experienced low glucose symptoms'),
                  value: _experiencedLow,
                  onChanged: (value) {
                    setState(() => _experiencedLow = value);
                  },
                ),
              TextFormField(
                controller: _notesController,
                maxLength: 500,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_saving ? 'Saving...' : 'Save workout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkoutHistoryPage extends StatelessWidget {
  const WorkoutHistoryPage({
    super.key,
    required this.userId,
    required this.repository,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
  });

  final String userId;
  final ExerciseRepository repository;
  final bool diabetesEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout history')),
      body: StreamBuilder<List<WorkoutSession>>(
        stream: repository.watchRecentSessions(userId, limit: 100),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ExerciseError(message: '${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('No completed workouts yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final session = snapshot.data![index];
              return WorkoutSessionTile(
                session: session,
                diabetesEnabled: diabetesEnabled,
                onDelete: () => repository.deleteSession(userId, session.id),
              );
            },
          );
        },
      ),
    );
  }
}

class WorkoutSessionTile extends StatelessWidget {
  const WorkoutSessionTile({
    super.key,
    required this.session,
    this.onDelete,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
  });

  final WorkoutSession session;
  final VoidCallback? onDelete;
  final bool diabetesEnabled;

  @override
  Widget build(BuildContext context) {
    final glucoseBefore = session.preWorkout.glucoseValue;
    final glucoseAfter = session.postWorkout.glucoseValue;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(session.activityType.icon)),
        title: Text(session.activityName),
        subtitle: Text(
          '${_formatDate(session.startedAt)} • ${_formatDuration(Duration(seconds: session.actualDurationSeconds))}'
          '${diabetesEnabled && glucoseBefore != null && glucoseAfter != null ? '\nGlucose: ${_formatNumber(glucoseBefore)} → ${_formatNumber(glucoseAfter)} ${session.preWorkout.glucoseUnit}' : ''}',
        ),
        isThreeLine:
            diabetesEnabled && glucoseBefore != null && glucoseAfter != null,
        trailing: onDelete == null
            ? Text(session.intensity.label)
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') onDelete!();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'delete', child: Text('Delete workout')),
                ],
              ),
      ),
    );
  }
}

class _ProfileProgressCard extends StatelessWidget {
  const _ProfileProgressCard({
    required this.userId,
    required this.repository,
    required this.activeMinutes,
    required this.strengthSessions,
    required this.diabetesEnabled,
  });

  final String userId;
  final ExerciseRepository repository;
  final int activeMinutes;
  final int strengthSessions;
  final bool diabetesEnabled;

  Future<void> _editProfile(
    BuildContext context,
    ExerciseProfile profile,
  ) async {
    final formKey = GlobalKey<FormState>();
    final minutesController = TextEditingController(
      text: profile.weeklyMinutesGoal.toString(),
    );
    final strengthController = TextEditingController(
      text: profile.weeklyStrengthGoal.toString(),
    );
    var glucoseUnit = profile.glucoseUnit;

    final updated = await showDialog<ExerciseProfile>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Exercise goals'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: minutesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Weekly active minutes',
                    ),
                    validator: (value) {
                      final number = int.tryParse(value ?? '');
                      return number == null || number < 5 || number > 1000
                          ? 'Enter 5–1000 minutes'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: strengthController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Weekly strength sessions',
                    ),
                    validator: (value) {
                      final number = int.tryParse(value ?? '');
                      return number == null || number < 0 || number > 14
                          ? 'Enter 0–14 sessions'
                          : null;
                    },
                  ),
                  if (diabetesEnabled) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: glucoseUnit,
                      decoration: const InputDecoration(
                        labelText: 'Glucose unit',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'mg/dL', child: Text('mg/dL')),
                        DropdownMenuItem(
                          value: 'mmol/L',
                          child: Text('mmol/L'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => glucoseUnit = value);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop(
                    ExerciseProfile(
                      weeklyMinutesGoal: int.parse(minutesController.text),
                      weeklyStrengthGoal: int.parse(strengthController.text),
                      glucoseUnit: glucoseUnit,
                      preWorkoutCheckEnabled: profile.preWorkoutCheckEnabled,
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    minutesController.dispose();
    strengthController.dispose();

    if (updated != null) {
      await repository.saveProfile(userId, updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ExerciseProfile>(
      stream: repository.watchProfile(userId),
      initialData: ExerciseProfile.defaults,
      builder: (context, snapshot) {
        final profile = snapshot.data ?? ExerciseProfile.defaults;
        return _WeeklyProgressCard(
          activeMinutes: activeMinutes,
          goalMinutes: profile.weeklyMinutesGoal,
          strengthSessions: strengthSessions,
          strengthGoal: profile.weeklyStrengthGoal,
          onSettings: () => _editProfile(context, profile),
          diabetesEnabled: diabetesEnabled,
        );
      },
    );
  }
}

class _WeeklyProgressCard extends StatelessWidget {
  const _WeeklyProgressCard({
    required this.activeMinutes,
    required this.goalMinutes,
    required this.strengthSessions,
    required this.strengthGoal,
    required this.onSettings,
    required this.diabetesEnabled,
  });

  final int activeMinutes;
  final int goalMinutes;
  final int strengthSessions;
  final int strengthGoal;
  final VoidCallback onSettings;
  final bool diabetesEnabled;

  @override
  Widget build(BuildContext context) {
    final progress = (activeMinutes / goalMinutes).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'This week',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: onSettings,
                  tooltip: 'Edit exercise goals',
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '$activeMinutes of $goalMinutes active minutes',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 12),
            Text('$strengthSessions of $strengthGoal strength sessions'),
            const SizedBox(height: 4),
            Text(
              diabetesEnabled
                  ? 'Build up gradually and use goals agreed on with your care team.'
                  : 'Build up gradually and choose goals that feel sustainable.',
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickStartCard extends StatelessWidget {
  const _QuickStartCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 32),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuidedStepCard extends StatelessWidget {
  const _GuidedStepCard({required this.routine, required this.elapsed});

  final WorkoutRoutine routine;
  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    var stepStartSeconds = 0;
    WorkoutStep? currentStep;
    var stepNumber = routine.steps.length;

    for (var index = 0; index < routine.steps.length; index++) {
      final step = routine.steps[index];
      if (elapsed.inSeconds < stepStartSeconds + step.durationSeconds) {
        currentStep = step;
        stepNumber = index + 1;
        break;
      }
      stepStartSeconds += step.durationSeconds;
    }

    if (currentStep == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.celebration),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Guided routine complete. Cool down as needed, then finish when you are ready.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final stepElapsed = elapsed.inSeconds - stepStartSeconds;
    final remaining = currentStep.durationSeconds - stepElapsed;
    final progress = (stepElapsed / currentStep.durationSeconds).clamp(
      0.0,
      1.0,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Step $stepNumber of ${routine.steps.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Text(
              currentStep.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(currentStep.instruction),
            if (currentStep.accessibilityAlternative != null) ...[
              const SizedBox(height: 8),
              Text(
                'Alternative: ${currentStep.accessibilityAlternative}',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 14),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Text('${_formatDuration(Duration(seconds: remaining))} remaining'),
          ],
        ),
      ),
    );
  }
}

class _RatingSlider extends StatelessWidget {
  const _RatingSlider({
    required this.label,
    required this.lowLabel,
    required this.highLabel,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String lowLabel;
  final String highLabel;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.round()}'),
        Slider(
          value: value,
          min: 1,
          max: 5,
          divisions: 4,
          label: value.round().toString(),
          onChanged: onChanged,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(lowLabel), Text(highLabel)],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _ExerciseError extends StatelessWidget {
  const _ExerciseError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

extension WorkoutActivityTypeUi on WorkoutActivityType {
  String get label => switch (this) {
    WorkoutActivityType.walking => 'Walking',
    WorkoutActivityType.running => 'Running',
    WorkoutActivityType.cycling => 'Cycling',
    WorkoutActivityType.swimming => 'Swimming',
    WorkoutActivityType.strength => 'Strength training',
    WorkoutActivityType.chairExercise => 'Chair exercise',
    WorkoutActivityType.yoga => 'Yoga',
    WorkoutActivityType.stretching => 'Stretching',
    WorkoutActivityType.sports => 'Sports',
    WorkoutActivityType.householdWork => 'Household work',
    WorkoutActivityType.errands => 'Errands',
    WorkoutActivityType.activeWork => 'Active work',
    WorkoutActivityType.movementBreak => 'Movement break',
    WorkoutActivityType.custom => 'Custom activity',
  };

  IconData get icon => switch (this) {
    WorkoutActivityType.walking => Icons.directions_walk,
    WorkoutActivityType.running => Icons.directions_run,
    WorkoutActivityType.cycling => Icons.directions_bike,
    WorkoutActivityType.swimming => Icons.pool,
    WorkoutActivityType.strength => Icons.fitness_center,
    WorkoutActivityType.chairExercise => Icons.accessible_forward,
    WorkoutActivityType.yoga => Icons.self_improvement,
    WorkoutActivityType.stretching => Icons.accessibility_new,
    WorkoutActivityType.sports => Icons.sports,
    WorkoutActivityType.householdWork => Icons.home_repair_service,
    WorkoutActivityType.errands => Icons.shopping_bag,
    WorkoutActivityType.activeWork => Icons.work,
    WorkoutActivityType.movementBreak => Icons.airline_seat_recline_normal,
    WorkoutActivityType.custom => Icons.sports,
  };
}

extension WorkoutIntensityUi on WorkoutIntensity {
  String get label => switch (this) {
    WorkoutIntensity.light => 'Light',
    WorkoutIntensity.moderate => 'Moderate',
    WorkoutIntensity.vigorous => 'Vigorous',
  };
}

DateTime _startOfWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

String? _mealRelation(int? minutesSinceMeal) {
  if (minutesSinceMeal == null) return null;
  if (minutesSinceMeal <= 30) return '0–30 minutes after meal';
  if (minutesSinceMeal <= 60) return '30–60 minutes after meal';
  return 'More than 60 minutes after meal';
}

String? _validateOptionalPositiveNumber(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final number = double.tryParse(value.trim());
  if (number == null || number < 0) {
    return 'Enter a valid positive number';
  }
  return null;
}

double? _optionalDouble(String value) {
  return value.trim().isEmpty ? null : double.tryParse(value.trim());
}

int? _optionalInt(String value) {
  return value.trim().isEmpty ? null : int.tryParse(value.trim());
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$month/$day/${date.year}';
}

String _formatNumber(double value) {
  return value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

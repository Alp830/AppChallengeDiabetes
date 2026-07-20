import 'package:flutter/material.dart';

import '../../app_features.dart';
import '../../cgm/data/glucose_repository.dart';
import '../../cgm/models/glucose_models.dart';
import '../../meals/data/meal_repository.dart';
import '../../meals/models/meal_models.dart';
import '../data/sleep_repository.dart';
import '../models/sleep_models.dart';
import '../services/bedtime_advisor_service.dart';
import '../services/overnight_analysis_service.dart';
import '../services/sleep_insight_service.dart';
import 'sleep_log_sheet.dart';

class SleepPage extends StatefulWidget {
  const SleepPage({
    super.key,
    required this.userId,
    this.sleepRepository,
    this.glucoseRepository,
    this.mealRepository,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
  });

  final String userId;
  final SleepRepository? sleepRepository;
  final GlucoseRepository? glucoseRepository;
  final MealRepository? mealRepository;
  final bool diabetesEnabled;

  @override
  State<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends State<SleepPage> {
  late final SleepRepository _sleep =
      widget.sleepRepository ?? SleepRepository();
  late final GlucoseRepository _glucose =
      widget.glucoseRepository ?? GlucoseRepository();
  late final MealRepository _meals = widget.mealRepository ?? MealRepository();

  static const _analysisService = OvernightAnalysisService();
  static const _insightService = SleepInsightService();
  static const _advisorService = BedtimeAdvisorService();

  Future<void> _changeFocus(SleepSettings current, SleepFocus focus) async {
    await _sleep.saveSettings(widget.userId, current.copyWith(focus: focus));
  }

  Future<void> _goToBed() async {
    await _sleep.startPendingBedtime(widget.userId, DateTime.now());
  }

  Future<void> _wakeUp(DateTime pendingBedtime) async {
    final result = await showModalBottomSheet<SleepLog>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SleepLogSheet(
        initialBedtime: pendingBedtime,
        initialWakeTime: DateTime.now(),
      ),
    );
    if (result != null) {
      await _sleep.saveSleepLog(widget.userId, result);
    }
    await _sleep.clearPendingBedtime(widget.userId);
  }

  Future<void> _logManually() async {
    final result = await showModalBottomSheet<SleepLog>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const SleepLogSheet(),
    );
    if (result != null) {
      await _sleep.saveSleepLog(widget.userId, result);
    }
  }

  Future<void> _edit(SleepLog log) async {
    final result = await showModalBottomSheet<SleepLog>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SleepLogSheet(initial: log),
    );
    if (result != null && result.id.isNotEmpty) {
      await _sleep.updateSleepLog(widget.userId, result.id, result);
    }
  }

  Future<void> _delete(SleepLog log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this night?'),
        content: const Text(
          'This removes the logged sleep for this night. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && log.id.isNotEmpty) {
      await _sleep.deleteSleepLog(widget.userId, log.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SleepSettings>(
      stream: _sleep.watchSettings(widget.userId),
      builder: (context, settingsSnapshot) {
        final settings = settingsSnapshot.data ?? const SleepSettings();
        return StreamBuilder<List<SleepLog>>(
          stream: _sleep.watchRecentSleep(widget.userId),
          builder: (context, logsSnapshot) {
            if (logsSnapshot.hasError) {
              return const _SleepError();
            }
            if (!logsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final logs = logsSnapshot.data!;
            return ListView(
              key: const Key('sleepPage'),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text('Sleep', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  widget.diabetesEnabled
                      ? 'How you sleep and how your glucose behaves overnight are closely linked.'
                      : 'Track your sleep and build a steadier nightly routine.',
                ),
                const SizedBox(height: 16),
                _LiveCaptureCard(
                  pendingBedtime: settings.pendingBedtime,
                  onGoToBed: _goToBed,
                  onWakeUp: _wakeUp,
                  onLogManually: _logManually,
                ),
                const SizedBox(height: 16),
                if (logs.isEmpty)
                  _EmptyState(diabetesEnabled: widget.diabetesEnabled)
                else if (!widget.diabetesEnabled)
                  _SleepContextView(
                    userId: widget.userId,
                    logs: logs,
                    hasGlucose: false,
                    diabetesEnabled: false,
                    sleepSettings: settings,
                    glucose: null,
                    meals: null,
                    analysisService: _analysisService,
                    insightService: _insightService,
                    advisorService: _advisorService,
                    onEdit: _edit,
                    onDelete: _delete,
                    onChangeFocus: (focus) => _changeFocus(settings, focus),
                  )
                else
                  StreamBuilder<bool>(
                    stream: _glucose.watchHasGlucoseData(widget.userId),
                    builder: (context, glucoseSnapshot) => _SleepContextView(
                      userId: widget.userId,
                      logs: logs,
                      hasGlucose: glucoseSnapshot.data ?? false,
                      diabetesEnabled: true,
                      sleepSettings: settings,
                      glucose: _glucose,
                      meals: _meals,
                      analysisService: _analysisService,
                      insightService: _insightService,
                      advisorService: _advisorService,
                      onEdit: _edit,
                      onDelete: _delete,
                      onChangeFocus: (focus) => _changeFocus(settings, focus),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Bundles the async-derived analysis so the view can render synchronously.
class _SleepContext {
  const _SleepContext({
    required this.settings,
    required this.lastNight,
    required this.advice,
    required this.insights,
    required this.showDinnerNudge,
  });

  final GlucoseSettings settings;
  final OvernightAnalysis lastNight;
  final BedtimeAdvice advice;
  final List<SleepInsight> insights;
  final bool showDinnerNudge;
}

class _SleepContextView extends StatefulWidget {
  const _SleepContextView({
    required this.userId,
    required this.logs,
    required this.hasGlucose,
    required this.diabetesEnabled,
    required this.sleepSettings,
    required this.glucose,
    required this.meals,
    required this.analysisService,
    required this.insightService,
    required this.advisorService,
    required this.onEdit,
    required this.onDelete,
    required this.onChangeFocus,
  });

  final String userId;
  final List<SleepLog> logs;

  /// Whether the user has imported glucose data. Gates every glucose-derived
  /// card; the sleep-log cards always show.
  final bool hasGlucose;
  final bool diabetesEnabled;
  final SleepSettings sleepSettings;
  final GlucoseRepository? glucose;
  final MealRepository? meals;
  final OvernightAnalysisService analysisService;
  final SleepInsightService insightService;
  final BedtimeAdvisorService advisorService;
  final Future<void> Function(SleepLog log) onEdit;
  final Future<void> Function(SleepLog log) onDelete;
  final Future<void> Function(SleepFocus focus) onChangeFocus;

  @override
  State<_SleepContextView> createState() => _SleepContextViewState();
}

class _SleepContextViewState extends State<_SleepContextView> {
  late Future<_SleepContext> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _SleepContextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recompute when the set of nights changes (new log, edit, delete).
    final oldKey = oldWidget.logs
        .map((log) => '${log.id}:${log.wakeTime}')
        .join('|');
    final newKey = widget.logs
        .map((log) => '${log.id}:${log.wakeTime}')
        .join('|');
    if (oldKey != newKey) {
      _future = _load();
    }
  }

  Future<_SleepContext> _load() async {
    final logs = widget.logs;
    final latest = logs.first;

    if (!widget.diabetesEnabled) {
      return _SleepContext(
        settings: const GlucoseSettings(),
        lastNight: OvernightAnalysis.noCoverage,
        advice: BedtimeAdvice.none,
        insights: widget.insightService.buildInsights(logs),
        showDinnerNudge: false,
      );
    }

    final glucose = widget.glucose!;
    final mealsRepository = widget.meals!;
    final glucoseSettings = await glucose.watchSettings(widget.userId).first;
    final meals = await mealsRepository.watchMeals(widget.userId).first;

    // One fetch spanning all recent nights (+ padding for pre-bed trend / morning).
    final rangeStart = logs.last.bedtime.subtract(const Duration(hours: 1));
    final rangeEnd = latest.wakeTime.add(const Duration(hours: 2));
    final readings = rangeEnd.isAfter(rangeStart)
        ? await glucose.getRange(widget.userId, rangeStart, rangeEnd)
        : <GlucoseReading>[];

    // Per-night analysis (sliced from the single fetch).
    final analyses = <String, OvernightAnalysis>{};
    final morningFasting = <String, double>{};
    for (final log in logs) {
      final dinner = _resolveDinner(meals, log.bedtime);
      analyses[log.id] = widget.analysisService.analyze(
        log,
        readings,
        settings: glucoseSettings,
        dinner: dinner,
      );
      final morning =
          readings
              .where(
                (reading) =>
                    !reading.timestamp.isBefore(log.wakeTime) &&
                    reading.timestamp.isBefore(
                      log.wakeTime.add(const Duration(hours: 2)),
                    ),
              )
              .toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (morning.isNotEmpty) {
        morningFasting[log.dateId] = morning.first.valueMgDl;
      }
    }

    final insights = widget.insightService.buildInsights(
      logs,
      morningFastingByDateId: morningFasting,
    );

    // S3: nudge only when late-dinner-hyperglycemia recurs.
    final lateDinnerNights = logs.where((log) {
      final analysis = analyses[log.id];
      return analysis != null &&
          analysis.phenotype == OvernightPhenotype.lateDinnerHyperglycemia;
    }).length;

    final lastNight = analyses[latest.id] ?? OvernightAnalysis.noCoverage;

    return _SleepContext(
      settings: glucoseSettings,
      lastNight: lastNight,
      advice: widget.advisorService.evaluate(
        lastNight,
        settings: glucoseSettings,
      ),
      insights: insights,
      showDinnerNudge: lateDinnerNights >= 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.logs.first;
    final focus = widget.sleepSettings.focus;
    return FutureBuilder<_SleepContext>(
      future: _future,
      builder: (context, snapshot) {
        final context0 = snapshot.data;
        final advice = context0?.advice ?? BedtimeAdvice.none;
        final hasGlucose = widget.hasGlucose;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LastNightCard(
              log: latest,
              analysis: context0?.lastNight,
              settings: context0?.settings ?? const GlucoseSettings(),
              loading: hasGlucose && !snapshot.hasData,
              showGlucose: hasGlucose,
              onEdit: () => widget.onEdit(latest),
            ),
            // The glucose-derived cards only appear once the user has glucose
            // data; the sleep-log cards below always show.
            // S8 · Nocturnal-low flag. Safety — always shown, never focus-gated.
            if (hasGlucose && advice.nocturnalLow != null) ...[
              const SizedBox(height: 16),
              _NocturnalLowCard(flag: advice.nocturnalLow!),
            ],
            // S7 · Conditional bedtime-snack advisor. Focus-gated (S9).
            if (hasGlucose &&
                advice.snackSuggestion != null &&
                widget.sleepSettings.showsSnackAdvisor) ...[
              const SizedBox(height: 16),
              _SnackAdvisorCard(suggestion: advice.snackSuggestion!),
            ],
            // S3 · Dinner-timing coach. Focus-gated (S9).
            if (hasGlucose &&
                context0 != null &&
                context0.showDinnerNudge &&
                widget.sleepSettings.showsDinnerCoach) ...[
              const SizedBox(height: 16),
              const _DinnerNudgeCard(),
            ],
            if (widget.diabetesEnabled &&
                context0 != null &&
                context0.insights.isNotEmpty) ...[
              const SizedBox(height: 16),
              _InsightsCard(insights: context0.insights),
            ],
            if (widget.diabetesEnabled) ...[
              const SizedBox(height: 16),
              // S9 · Quiet-overnight / tiered focus selector.
              _FocusCard(focus: focus, onChangeFocus: widget.onChangeFocus),
            ],
            const SizedBox(height: 24),
            Text(
              'Recent nights',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final log in widget.logs.take(10))
              _NightTile(
                log: log,
                onEdit: () => widget.onEdit(log),
                onDelete: () => widget.onDelete(log),
              ),
          ],
        );
      },
    );
  }
}

MealEvent? _resolveDinner(List<MealEvent> meals, DateTime bedtime) {
  final windowStart = bedtime.subtract(const Duration(hours: 8));
  final candidates =
      meals
          .where(
            (meal) =>
                meal.timestamp.isAfter(windowStart) &&
                !meal.timestamp.isAfter(bedtime),
          )
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (candidates.isEmpty) return null;
  final tagged = candidates
      .where((meal) => meal.mealType.toLowerCase() == 'dinner')
      .toList();
  return tagged.isNotEmpty ? tagged.last : candidates.last;
}

class _LiveCaptureCard extends StatelessWidget {
  const _LiveCaptureCard({
    required this.pendingBedtime,
    required this.onGoToBed,
    required this.onWakeUp,
    required this.onLogManually,
  });

  final DateTime? pendingBedtime;
  final Future<void> Function() onGoToBed;
  final Future<void> Function(DateTime pendingBedtime) onWakeUp;
  final Future<void> Function() onLogManually;

  @override
  Widget build(BuildContext context) {
    final pending = pendingBedtime;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pending == null) ...[
              Text('Good night', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Tap when you head to bed, or log a past night by hand.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('goToBedButton'),
                onPressed: onGoToBed,
                icon: const Icon(Icons.bedtime),
                label: const Text("I'm going to bed"),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('logSleepButton'),
                onPressed: onLogManually,
                icon: const Icon(Icons.edit_calendar),
                label: const Text('Log last night'),
              ),
            ] else ...[
              Text('Sleeping', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('You went to bed at ${_time(pending)}. Sleep well.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('wakeUpButton'),
                onPressed: () => onWakeUp(pending),
                icon: const Icon(Icons.wb_sunny),
                label: const Text("I'm awake"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LastNightCard extends StatelessWidget {
  const _LastNightCard({
    required this.log,
    required this.analysis,
    required this.settings,
    required this.loading,
    required this.showGlucose,
    required this.onEdit,
  });

  final SleepLog log;
  final OvernightAnalysis? analysis;
  final GlucoseSettings settings;
  final bool loading;

  /// When false the card shows only the sleep duration/quality line — no
  /// overnight-glucose timeline, phenotype, or stats.
  final bool showGlucose;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('lastNightCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Last night', style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: onEdit,
                  tooltip: 'Edit night',
                  icon: const Icon(Icons.edit),
                ),
              ],
            ),
            Text(
              '${log.durationHours}h ${log.durationRemainderMinutes}m in bed'
              ' · quality ${log.quality}/5'
              '${log.wakeUps > 0 ? ' · woke ${log.wakeUps}x' : ''}',
              style: theme.textTheme.bodyLarge,
            ),
            if (showGlucose) ...[
              const SizedBox(height: 12),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (analysis == null || !analysis!.hasCoverage) ...[
                Text(
                  OvernightPhenotype.insufficientData.summary,
                  style: theme.textTheme.bodyMedium,
                ),
              ] else ...[
                SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _OvernightTimelinePainter(
                      log: log,
                      analysis: analysis!,
                      settings: settings,
                      colors: theme.colorScheme,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  analysis!.phenotype.label,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(analysis!.phenotype.summary),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Stat(
                      label: 'In range',
                      value: '${analysis!.timeInRangePercent!.round()}%',
                    ),
                    _Stat(
                      label: 'Lowest',
                      value: _mgdl(analysis!.lowestMgDl!, settings),
                    ),
                    if (analysis!.lowEventCount > 0)
                      _Stat(label: 'Lows', value: '${analysis!.lowEventCount}'),
                    _Stat(
                      label: 'Variability',
                      value: '${analysis!.cvPercent!.round()}%',
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleMedium),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _DinnerNudgeCard extends StatelessWidget {
  const _DinnerNudgeCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dinner_dining),
                const SizedBox(width: 8),
                Text(
                  'A gentle idea',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'On a few recent nights your glucose ran higher after a late dinner. '
              'Finishing dinner a bit earlier tends to steady overnight glucose — '
              'entirely your call.',
            ),
          ],
        ),
      ),
    );
  }
}

/// S8 · Nocturnal-low flag. Gentle by design — surfaces a safety observation
/// without alarming, and never tells the user what to do about it.
class _NocturnalLowCard extends StatelessWidget {
  const _NocturnalLowCard({required this.flag});

  final NocturnalLowFlag flag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final severe = flag.severity == NocturnalLowSeverity.severe;
    return Card(
      key: const Key('nocturnalLowCard'),
      color: severe
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  severe ? Icons.warning_amber : Icons.trending_down,
                  color: severe ? theme.colorScheme.onErrorContainer : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(flag.title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(flag.message),
          ],
        ),
      ),
    );
  }
}

/// S7 · Conditional bedtime-snack advisor. Only ever rendered when the rules
/// engine already decided the narrow pattern applies. Always optional, always
/// carries the clinician note.
class _SnackAdvisorCard extends StatelessWidget {
  const _SnackAdvisorCard({required this.suggestion});

  final BedtimeSnackSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('snackAdvisorCard'),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.nightlight_round),
                const SizedBox(width: 8),
                Text(
                  'An optional bedtime idea',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(suggestion.message),
            const SizedBox(height: 8),
            Text(
              BedtimeSnackSuggestion.clinicianNote,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// S9 · Quiet-overnight / tiered focus. Lets the user tell the app what to
/// emphasize so it stays quiet rather than noisy.
class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.focus, required this.onChangeFocus});

  final SleepFocus focus;
  final Future<void> Function(SleepFocus focus) onChangeFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('sleepFocusCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What should sleep focus on?',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'The app stays quiet overnight either way — this just tunes the '
              'gentle nudges. Overnight lows always surface for safety.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final option in SleepFocus.values)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: option == focus,
                    onSelected: (selected) {
                      if (selected && option != focus) onChangeFocus(option);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(focus.description, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.insights});

  final List<SleepInsight> insights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your patterns', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            for (var index = 0; index < insights.length; index++) ...[
              if (index > 0) const Divider(),
              Text(insights[index].title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(insights[index].message),
            ],
          ],
        ),
      ),
    );
  }
}

class _NightTile extends StatelessWidget {
  const _NightTile({
    required this.log,
    required this.onEdit,
    required this.onDelete,
  });

  final SleepLog log;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.bedtime)),
        title: Text('${log.durationHours}h ${log.durationRemainderMinutes}m'),
        subtitle: Text(
          '${_dateLabel(log.wakeTime)} · quality ${log.quality}/5'
          '${log.wakeUps > 0 ? ' · woke ${log.wakeUps}x' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onEdit,
              tooltip: 'Edit night',
              icon: const Icon(Icons.edit),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete night',
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.diabetesEnabled});

  final bool diabetesEnabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.nights_stay_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              'No nights logged yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              diabetesEnabled
                  ? 'Log a night to see how your sleep and overnight glucose line up. Import LibreView data first to unlock the glucose view.'
                  : 'Log a night to begin tracking your sleep duration and quality.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SleepError extends StatelessWidget {
  const _SleepError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load your sleep data. Check your connection and try again.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _OvernightTimelinePainter extends CustomPainter {
  _OvernightTimelinePainter({
    required this.log,
    required this.analysis,
    required this.settings,
    required this.colors,
  });

  final SleepLog log;
  final OvernightAnalysis analysis;
  final GlucoseSettings settings;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    // The painter only draws a stylized band + summary line based on the
    // analysis envelope (mean / lowest / highest) so it stays cheap and does
    // not need the raw reading list threaded through.
    const left = 8.0;
    const top = 12.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left * 2,
      size.height - 34,
    );

    final low = settings.lowMgDl;
    final high = settings.highMgDl;
    final minimum = (analysis.lowestMgDl ?? low) - 20;
    final maximum = (analysis.highestMgDl ?? high) + 20;
    final span = (maximum - minimum) < 60 ? 60.0 : (maximum - minimum);

    double y(double value) =>
        chart.bottom - ((value - minimum) / span).clamp(0, 1) * chart.height;

    // Target range band.
    canvas.drawRect(
      Rect.fromLTRB(chart.left, y(high), chart.right, y(low)),
      Paint()..color = colors.primaryContainer.withValues(alpha: .45),
    );

    // Envelope band from lowest to highest.
    if (analysis.lowestMgDl != null && analysis.highestMgDl != null) {
      canvas.drawRect(
        Rect.fromLTRB(
          chart.left,
          y(analysis.highestMgDl!),
          chart.right,
          y(analysis.lowestMgDl!),
        ),
        Paint()..color = colors.primary.withValues(alpha: .12),
      );
    }

    // Mean line.
    if (analysis.meanMgDl != null) {
      final meanY = y(analysis.meanMgDl!);
      canvas.drawLine(
        Offset(chart.left, meanY),
        Offset(chart.right, meanY),
        Paint()
          ..color = colors.primary
          ..strokeWidth = 2.5,
      );
    }

    // Bed / wake axis ticks.
    final grid = Paint()..color = colors.outlineVariant;
    canvas.drawLine(
      Offset(chart.left, chart.bottom),
      Offset(chart.right, chart.bottom),
      grid,
    );
  }

  @override
  bool shouldRepaint(covariant _OvernightTimelinePainter oldDelegate) => true;
}

String _mgdl(double mgDl, GlucoseSettings settings) {
  final value = glucoseForDisplay(mgDl, settings.displayUnit);
  return '${value.toStringAsFixed(settings.displayUnit == 'mmol/L' ? 1 : 0)} ${settings.displayUnit}';
}

String _time(DateTime date) {
  final hour = date.hour == 0
      ? 12
      : (date.hour > 12 ? date.hour - 12 : date.hour);
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
}

String _dateLabel(DateTime date) => '${date.month}/${date.day}';

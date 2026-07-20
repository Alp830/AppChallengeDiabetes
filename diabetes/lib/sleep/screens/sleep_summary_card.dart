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

/// S10 · A compact "Last night" card for the Today dashboard, sitting beside
/// Activity and Glucose so sleep isn't siloed. Tapping it opens the Sleep tab.
class SleepSummaryCard extends StatefulWidget {
  const SleepSummaryCard({
    super.key,
    required this.userId,
    required this.onOpenSleep,
    this.sleepRepository,
    this.glucoseRepository,
    this.mealRepository,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
  });

  final String userId;
  final VoidCallback onOpenSleep;
  final SleepRepository? sleepRepository;
  final GlucoseRepository? glucoseRepository;
  final MealRepository? mealRepository;
  final bool diabetesEnabled;

  @override
  State<SleepSummaryCard> createState() => _SleepSummaryCardState();
}

class _SleepSummaryCardState extends State<SleepSummaryCard> {
  late final SleepRepository _sleep =
      widget.sleepRepository ?? SleepRepository();
  late final GlucoseRepository _glucose =
      widget.glucoseRepository ?? GlucoseRepository();
  late final MealRepository _meals = widget.mealRepository ?? MealRepository();

  static const _analysisService = OvernightAnalysisService();
  static const _advisorService = BedtimeAdvisorService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SleepLog?>(
      stream: _sleep.watchLatest(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        if (!snapshot.hasData) {
          return _Shell(
            onOpenSleep: widget.onOpenSleep,
            child: const _Loading(),
          );
        }
        final log = snapshot.data;
        if (log == null) {
          return _Shell(
            onOpenSleep: widget.onOpenSleep,
            child: Text(
              widget.diabetesEnabled
                  ? 'No nights logged yet. Tap to log how you slept and see your overnight glucose story.'
                  : 'No nights logged yet. Tap to log how you slept.',
            ),
          );
        }
        if (!widget.diabetesEnabled) {
          return _Shell(
            onOpenSleep: widget.onOpenSleep,
            child: _SummaryBody(log: log, future: null),
          );
        }
        // The overnight-glucose lines only appear once the user has glucose
        // data; the sleep duration/quality line always shows.
        return StreamBuilder<bool>(
          stream: _glucose.watchHasGlucoseData(widget.userId),
          builder: (context, glucoseSnapshot) {
            final showGlucose = glucoseSnapshot.data ?? false;
            return _Shell(
              onOpenSleep: widget.onOpenSleep,
              child: _SummaryBody(
                log: log,
                future: showGlucose ? _load(log) : null,
              ),
            );
          },
        );
      },
    );
  }

  Future<_NightSummary> _load(SleepLog log) async {
    final glucoseSettings = await _glucose.watchSettings(widget.userId).first;
    final readings = await _glucose.getRange(
      widget.userId,
      log.bedtime.subtract(const Duration(hours: 1)),
      log.wakeTime.add(const Duration(hours: 1)),
    );
    final meals = await _meals.watchMeals(widget.userId).first;
    final dinner = _resolveDinner(meals, log.bedtime);
    final analysis = _analysisService.analyze(
      log,
      readings,
      settings: glucoseSettings,
      dinner: dinner,
    );
    return _NightSummary(
      settings: glucoseSettings,
      analysis: analysis,
      advice: _advisorService.evaluate(analysis, settings: glucoseSettings),
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

class _NightSummary {
  const _NightSummary({
    required this.settings,
    required this.analysis,
    required this.advice,
  });

  final GlucoseSettings settings;
  final OvernightAnalysis analysis;
  final BedtimeAdvice advice;
}

class _Shell extends StatelessWidget {
  const _Shell({required this.onOpenSleep, required this.child});

  final VoidCallback onOpenSleep;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('sleepSummaryCard'),
      child: InkWell(
        onTap: onOpenSleep,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bedtime),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Last night',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.log, required this.future});

  final SleepLog log;

  /// Null when the user has no glucose data — the glucose lines are omitted.
  final Future<_NightSummary>? future;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final future = this.future;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${log.durationHours}h ${log.durationRemainderMinutes}m in bed'
          ' · quality ${log.quality}/5'
          '${log.wakeUps > 0 ? ' · woke ${log.wakeUps}x' : ''}',
          style: theme.textTheme.bodyLarge,
        ),
        if (future != null) ...[
          const SizedBox(height: 8),
          FutureBuilder<_NightSummary>(
            future: future,
            builder: (context, snapshot) {
              final summary = snapshot.data;
              if (summary == null) {
                return Text(
                  'Reading your overnight glucose…',
                  style: theme.textTheme.bodyMedium,
                );
              }
              final analysis = summary.analysis;
              if (!analysis.hasCoverage) {
                return Text(
                  OvernightPhenotype.insufficientData.summary,
                  style: theme.textTheme.bodyMedium,
                );
              }
              final low = summary.advice.nocturnalLow;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    analysis.phenotype.label,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'In range ${analysis.timeInRangePercent!.round()}%'
                    ' · lowest ${_mgdl(analysis.lowestMgDl!, summary.settings)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (low != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          low.severity == NocturnalLowSeverity.severe
                              ? Icons.warning_amber
                              : Icons.trending_down,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            low.title,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

String _mgdl(double mgDl, GlucoseSettings settings) {
  final value = glucoseForDisplay(mgDl, settings.displayUnit);
  return '${value.toStringAsFixed(settings.displayUnit == 'mmol/L' ? 1 : 0)} ${settings.displayUnit}';
}

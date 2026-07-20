import '../../cgm/data/glucose_repository.dart';
import '../../cgm/models/glucose_models.dart';
import '../../meals/data/meal_repository.dart';
import '../../meals/models/meal_models.dart';
import '../data/sleep_repository.dart';
import 'overnight_analysis_service.dart';

/// A compact, soft summary of the user's recent overnight glucose phenotype,
/// threaded into the food agent (F4). It lets evening recommendations adapt to
/// how this user's nights actually go — the app informs, it never prescribes.
class OvernightPhenotypeSummary {
  const OvernightPhenotypeSummary({
    required this.nightsAnalyzed,
    required this.dominant,
    required this.recurringLateDinnerHighs,
    required this.recurringLows,
  });

  /// Nights with real glucose coverage that fed this summary.
  final int nightsAnalyzed;

  /// The phenotype that showed up most across those nights.
  final OvernightPhenotype dominant;

  /// Late/large dinners were repeatedly followed by higher overnight glucose.
  final bool recurringLateDinnerHighs;

  /// Overnight lows recurred — a reason not to push very low-carb dinners.
  final bool recurringLows;

  /// A no-signal summary the food agent can silently fall back to.
  static const OvernightPhenotypeSummary none = OvernightPhenotypeSummary(
    nightsAnalyzed: 0,
    dominant: OvernightPhenotype.insufficientData,
    recurringLateDinnerHighs: false,
    recurringLows: false,
  );

  /// Enough recent, real nights to say anything at all.
  bool get hasSignal =>
      nightsAnalyzed >= 2 && dominant != OvernightPhenotype.insufficientData;

  /// One or two soft, non-clinical sentences written for the food agent to
  /// read. Empty when there is no signal.
  String get promptContext {
    if (!hasSignal) return '';
    final buffer = StringBuffer()
      ..write('Over the last $nightsAnalyzed nights with glucose data, this ')
      ..write("user's overnight pattern most often looked like ")
      ..write('"${dominant.label}" — ${dominant.summary}');
    if (recurringLateDinnerHighs &&
        dominant != OvernightPhenotype.lateDinnerHyperglycemia) {
      buffer.write(
        ' Late or large dinners have repeatedly been followed by higher '
        'overnight glucose for them.',
      );
    }
    if (recurringLows && dominant != OvernightPhenotype.frequentLows) {
      buffer.write(
        ' They have also had some overnight lows recently, so do not push very '
        'low-carb evening meals.',
      );
    }
    return buffer.toString();
  }
}

/// Builds an [OvernightPhenotypeSummary] from the user's recent nights, reusing
/// the S2 [OvernightAnalysisService]. Kept separate from the food agent so
/// `main.dart` stays decoupled from the sleep/glucose repositories.
class EveningFoodContextService {
  const EveningFoodContextService();

  static const _analysis = OvernightAnalysisService();

  /// Loads recent nights and reduces them to a single soft summary. Returns
  /// [OvernightPhenotypeSummary.none] (never throws on missing data) so callers
  /// can treat "no context" and "context loaded" the same way.
  Future<OvernightPhenotypeSummary> loadRecent(
    String userId, {
    SleepRepository? sleepRepository,
    GlucoseRepository? glucoseRepository,
    MealRepository? mealRepository,
    int maxNights = 14,
  }) async {
    final sleep = sleepRepository ?? SleepRepository();
    final glucose = glucoseRepository ?? GlucoseRepository();
    final meals = mealRepository ?? MealRepository();

    final logs = await sleep.watchRecentSleep(userId, limit: maxNights).first;
    if (logs.isEmpty) return OvernightPhenotypeSummary.none;

    final glucoseSettings = await glucose.watchSettings(userId).first;
    final mealEvents = await meals.watchMeals(userId).first;

    // One fetch spanning all recent nights (+ padding for the pre-bed trend).
    final rangeStart = logs.last.bedtime.subtract(const Duration(hours: 1));
    final rangeEnd = logs.first.wakeTime.add(const Duration(hours: 2));
    final readings = rangeEnd.isAfter(rangeStart)
        ? await glucose.getRange(userId, rangeStart, rangeEnd)
        : <GlucoseReading>[];

    final phenotypes = <OvernightPhenotype>[];
    for (final log in logs) {
      final analysis = _analysis.analyze(
        log,
        readings,
        settings: glucoseSettings,
        dinner: _resolveDinner(mealEvents, log.bedtime),
      );
      if (analysis.hasCoverage &&
          analysis.phenotype != OvernightPhenotype.insufficientData) {
        phenotypes.add(analysis.phenotype);
      }
    }

    if (phenotypes.isEmpty) return OvernightPhenotypeSummary.none;

    return OvernightPhenotypeSummary(
      nightsAnalyzed: phenotypes.length,
      dominant: _mode(phenotypes),
      recurringLateDinnerHighs:
          _count(phenotypes, OvernightPhenotype.lateDinnerHyperglycemia) >= 2,
      recurringLows: _count(phenotypes, OvernightPhenotype.frequentLows) >= 2,
    );
  }

  int _count(List<OvernightPhenotype> values, OvernightPhenotype target) =>
      values.where((value) => value == target).length;

  /// Most frequent phenotype; on a tie a meaningful pattern beats "steady" so a
  /// real signal is not washed out by calm nights.
  OvernightPhenotype _mode(List<OvernightPhenotype> values) {
    final counts = <OvernightPhenotype, int>{};
    for (final value in values) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        if (a.key == OvernightPhenotype.steady) return 1;
        if (b.key == OvernightPhenotype.steady) return -1;
        return 0;
      });
    return ranked.first.key;
  }
}

/// The meal most likely to be "dinner" before [bedtime]. Mirrors the resolver
/// used by the sleep page so both surfaces agree on which meal was dinner.
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

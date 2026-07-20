import '../../cgm/models/glucose_models.dart';
import 'overnight_analysis_service.dart';

/// How serious an overnight-low pattern is. Severe means readings dipped below
/// the consensus 54 mg/dL line; mild covers the 54–70 band.
enum NocturnalLowSeverity { mild, severe }

/// S8 · Nocturnal-low flag. A gentle, non-alarming surfacing of overnight lows
/// already computed by [OvernightAnalysisService]. This is a safety observation,
/// never a treatment instruction.
class NocturnalLowFlag {
  const NocturnalLowFlag({
    required this.severity,
    required this.eventCount,
    required this.lowestMgDl,
    required this.timeBelow70Percent,
    required this.timeBelow54Percent,
  });

  final NocturnalLowSeverity severity;

  /// Distinct sustained dips below the low threshold overnight.
  final int eventCount;
  final double lowestMgDl;
  final double timeBelow70Percent;
  final double timeBelow54Percent;

  String get title => severity == NocturnalLowSeverity.severe
      ? 'A notable low overnight'
      : 'Some low readings overnight';

  String get message {
    final events = eventCount == 1
        ? 'one dip'
        : eventCount > 1
        ? '$eventCount dips'
        : 'a stretch';
    if (severity == NocturnalLowSeverity.severe) {
      return 'Your glucose fell into a lower range while you slept ($events below your low mark). '
          'Overnight lows can disrupt sleep and matter for safety — worth sharing with your care team.';
    }
    return 'There ${eventCount == 1 ? 'was' : 'were'} $events below your low mark overnight. '
        'Nothing alarming on its own, but a pattern is worth a mention at your next check-in.';
  }
}

/// S7 · Conditional bedtime-snack suggestion. Deliberately narrow: only when
/// pre-bed glucose is low-normal and drifting down. Never routine — the report
/// is explicit that reflexive late snacking worsens overnight glycemia.
class BedtimeSnackSuggestion {
  const BedtimeSnackSuggestion({required this.preBedMgDl, required this.message});

  final double preBedMgDl;
  final String message;

  /// Shown alongside every suggestion. This app does not dose.
  static const String clinicianNote =
      'This is an optional idea, not medical advice. Check with your clinician '
      'about how to handle low-trending glucose before bed.';
}

/// The full bedtime-safety picture for one night, combining S8 (lows) and
/// S7 (an optional snack idea).
class BedtimeAdvice {
  const BedtimeAdvice({this.nocturnalLow, this.snackSuggestion});

  final NocturnalLowFlag? nocturnalLow;
  final BedtimeSnackSuggestion? snackSuggestion;

  bool get hasAnything => nocturnalLow != null || snackSuggestion != null;

  static const BedtimeAdvice none = BedtimeAdvice();
}

/// A small, transparent rules engine — not autonomous dosing. Turns an
/// [OvernightAnalysis] into the S7/S8 safety layer.
class BedtimeAdvisorService {
  const BedtimeAdvisorService();

  /// Consensus severe-low threshold (mg/dL).
  static const double _severeLow = 54;

  /// How far above the low threshold still counts as "low-normal" pre-bed.
  static const double _lowNormalBand = 45;

  BedtimeAdvice evaluate(
    OvernightAnalysis analysis, {
    GlucoseSettings settings = const GlucoseSettings(),
  }) {
    if (!analysis.hasCoverage) return BedtimeAdvice.none;
    return BedtimeAdvice(
      nocturnalLow: _nocturnalLow(analysis, settings),
      snackSuggestion: _snackSuggestion(analysis, settings),
    );
  }

  NocturnalLowFlag? _nocturnalLow(
    OvernightAnalysis analysis,
    GlucoseSettings settings,
  ) {
    final timeBelow70 = analysis.timeBelow70Percent ?? 0;
    final timeBelow54 = analysis.timeBelow54Percent ?? 0;
    final lowest = analysis.lowestMgDl ?? settings.lowMgDl;

    final hasSevere = timeBelow54 > 0 || lowest < _severeLow;
    final hasMild = analysis.lowEventCount > 0 || timeBelow70 >= 1;
    if (!hasSevere && !hasMild) return null;

    return NocturnalLowFlag(
      severity: hasSevere
          ? NocturnalLowSeverity.severe
          : NocturnalLowSeverity.mild,
      // A run below the line always represents at least one event, even when the
      // dip was too brief to be counted as sustained.
      eventCount: analysis.lowEventCount == 0 ? 1 : analysis.lowEventCount,
      lowestMgDl: lowest,
      timeBelow70Percent: timeBelow70,
      timeBelow54Percent: timeBelow54,
    );
  }

  BedtimeSnackSuggestion? _snackSuggestion(
    OvernightAnalysis analysis,
    GlucoseSettings settings,
  ) {
    final preBed = analysis.preBedMgDl;
    if (preBed == null) return null;

    final low = settings.lowMgDl;
    final trendingDown = analysis.bedtimeTrend == GlucoseTrend.falling;
    // Low-normal = above the low line (not already low) but within a short reach
    // of it. Combined with a downward drift, this is the one window the report
    // sanctions a small protein-forward snack.
    final lowNormal = preBed >= low && preBed <= low + _lowNormalBand;
    if (!trendingDown || !lowNormal) return null;

    return BedtimeSnackSuggestion(
      preBedMgDl: preBed,
      message:
          'Your glucose was low-normal and drifting down as you headed to bed. '
          'On nights like this — often after evening activity — a small '
          'protein-forward snack (a few nuts, plain yogurt, cheese) can steady '
          'things overnight. Only if it feels right for you.',
    );
  }
}

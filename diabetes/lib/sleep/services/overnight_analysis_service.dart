import 'dart:math';

import '../../cgm/models/glucose_models.dart';
import '../../meals/models/meal_models.dart';
import '../models/sleep_models.dart';

/// Direction of glucose around bedtime.
enum GlucoseTrend { rising, flat, falling }

/// A gentle, non-clinical classification of an overnight glucose pattern.
/// These are observations, never diagnoses.
enum OvernightPhenotype {
  steady,
  lateDinnerHyperglycemia,
  downwardPreBed,
  highVariability,
  frequentLows,
  insufficientData,
}

extension OvernightPhenotypeDisplay on OvernightPhenotype {
  String get label {
    switch (this) {
      case OvernightPhenotype.steady:
        return 'Steady night';
      case OvernightPhenotype.lateDinnerHyperglycemia:
        return 'Higher after a late dinner';
      case OvernightPhenotype.downwardPreBed:
        return 'Drifting down at bedtime';
      case OvernightPhenotype.highVariability:
        return 'A bumpier night';
      case OvernightPhenotype.frequentLows:
        return 'Some overnight lows';
      case OvernightPhenotype.insufficientData:
        return 'Not enough glucose data';
    }
  }

  /// Soft, plain-language framing. Not medical advice.
  String get summary {
    switch (this) {
      case OvernightPhenotype.steady:
        return 'Your glucose stayed fairly flat and in range while you slept.';
      case OvernightPhenotype.lateDinnerHyperglycemia:
        return 'Glucose ran higher early in the night, which can follow a large or late dinner.';
      case OvernightPhenotype.downwardPreBed:
        return 'Glucose was trending down as you went to bed — worth a glance before sleep.';
      case OvernightPhenotype.highVariability:
        return 'Glucose swung around more than usual overnight.';
      case OvernightPhenotype.frequentLows:
        return 'There were some low readings overnight. Consider sharing these with your care team.';
      case OvernightPhenotype.insufficientData:
        return 'Import overnight glucose to see how your night looked.';
    }
  }
}

/// Result of analyzing one night's overnight glucose.
class OvernightAnalysis {
  const OvernightAnalysis({
    required this.hasCoverage,
    required this.readingCount,
    required this.phenotype,
    this.meanMgDl,
    this.lowestMgDl,
    this.highestMgDl,
    this.timeInRangePercent,
    this.timeBelow70Percent,
    this.timeBelow54Percent,
    this.timeAbovePercent,
    this.cvPercent,
    this.lowEventCount = 0,
    this.bedtimeTrend = GlucoseTrend.flat,
    this.preBedMgDl,
    this.dinnerToBedMinutes,
  });

  final bool hasCoverage;
  final int readingCount;
  final OvernightPhenotype phenotype;

  final double? meanMgDl;
  final double? lowestMgDl;
  final double? highestMgDl;
  final double? timeInRangePercent;
  final double? timeBelow70Percent;
  final double? timeBelow54Percent;
  final double? timeAbovePercent;
  final double? cvPercent;
  final int lowEventCount;
  final GlucoseTrend bedtimeTrend;

  /// Glucose (mg/dL) around bedtime — the last reading in the pre-bed window.
  /// Drives the bedtime-snack advisor's "low-normal pre-bed" rule (S7).
  final double? preBedMgDl;

  /// Minutes between the resolved dinner and bedtime, when both are known.
  final int? dinnerToBedMinutes;

  static const OvernightAnalysis noCoverage = OvernightAnalysis(
    hasCoverage: false,
    readingCount: 0,
    phenotype: OvernightPhenotype.insufficientData,
  );
}

class OvernightAnalysisService {
  const OvernightAnalysisService();

  /// Consensus glycemic-variability target. CV above this reads as "bumpy".
  static const double _cvTarget = 36;

  /// Consensus severe-low threshold (mg/dL).
  static const double _severeLow = 54;

  /// Analyze the [log]'s overnight window against [readings]. Callers should
  /// pass readings spanning roughly [bedtime - 1h, wakeTime + 1h] (e.g. from
  /// [GlucoseRepository.getRange]) so the pre-bed trend has context.
  OvernightAnalysis analyze(
    SleepLog log,
    List<GlucoseReading> readings, {
    GlucoseSettings settings = const GlucoseSettings(),
    MealEvent? dinner,
  }) {
    final low = settings.lowMgDl;
    final high = settings.highMgDl;

    final overnight = readings
        .where(
          (reading) =>
              !reading.timestamp.isBefore(log.bedtime) &&
              !reading.timestamp.isAfter(log.wakeTime),
        )
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final dinnerToBed = dinner == null
        ? null
        : log.bedtime.difference(dinner.timestamp).inMinutes;

    if (overnight.length < 3) {
      return OvernightAnalysis(
        hasCoverage: false,
        readingCount: overnight.length,
        phenotype: OvernightPhenotype.insufficientData,
        dinnerToBedMinutes: dinnerToBed,
      );
    }

    final values = overnight.map((reading) => reading.valueMgDl).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final lowest = values.reduce(min);
    final highest = values.reduce(max);
    final cv = mean == 0 ? 0.0 : _standardDeviation(values, mean) / mean * 100;

    // Minute-bucketing: sum the gap before each reading (clamped 0..30) into a
    // range bucket keyed on the leading value. Mirrors MealAnalysisService.
    var minutesTotal = 0;
    var minutesInRange = 0;
    var minutesAbove = 0;
    var minutesBelow70 = 0;
    var minutesBelow54 = 0;
    for (var index = 1; index < overnight.length; index++) {
      final minutes = overnight[index].timestamp
          .difference(overnight[index - 1].timestamp)
          .inMinutes
          .clamp(0, 30);
      final value = overnight[index - 1].valueMgDl;
      minutesTotal += minutes;
      if (value < _severeLow) {
        minutesBelow54 += minutes;
        minutesBelow70 += minutes;
      } else if (value < low) {
        minutesBelow70 += minutes;
      } else if (value > high) {
        minutesAbove += minutes;
      } else {
        minutesInRange += minutes;
      }
    }
    final total = minutesTotal == 0 ? 1 : minutesTotal;
    final timeInRange = minutesInRange / total * 100;
    final timeAbove = minutesAbove / total * 100;
    final timeBelow70 = minutesBelow70 / total * 100;
    final timeBelow54 = minutesBelow54 / total * 100;

    final lowEventCount = _countLowEvents(overnight, low);
    final trend = _bedtimeTrend(readings, log.bedtime);
    final preBed = _preBedMgDl(readings, log.bedtime);

    final phenotype = _classify(
      readingCount: overnight.length,
      timeBelow70: timeBelow70,
      lowEventCount: lowEventCount,
      trend: trend,
      lowest: lowest,
      low: low,
      cv: cv,
      dinner: dinner,
      dinnerToBedMinutes: dinnerToBed,
      overnight: overnight,
      bedtime: log.bedtime,
      high: high,
    );

    return OvernightAnalysis(
      hasCoverage: true,
      readingCount: overnight.length,
      phenotype: phenotype,
      meanMgDl: mean,
      lowestMgDl: lowest,
      highestMgDl: highest,
      timeInRangePercent: timeInRange,
      timeBelow70Percent: timeBelow70,
      timeBelow54Percent: timeBelow54,
      timeAbovePercent: timeAbove,
      cvPercent: cv,
      lowEventCount: lowEventCount,
      bedtimeTrend: trend,
      preBedMgDl: preBed,
      dinnerToBedMinutes: dinnerToBed,
    );
  }

  OvernightPhenotype _classify({
    required int readingCount,
    required double timeBelow70,
    required int lowEventCount,
    required GlucoseTrend trend,
    required double lowest,
    required double low,
    required double cv,
    required MealEvent? dinner,
    required int? dinnerToBedMinutes,
    required List<GlucoseReading> overnight,
    required DateTime bedtime,
    required double high,
  }) {
    if (readingCount < 10) return OvernightPhenotype.insufficientData;

    // Safety-first ordering.
    if (timeBelow70 > 4 || lowEventCount >= 2) {
      return OvernightPhenotype.frequentLows;
    }
    if (trend == GlucoseTrend.falling && lowest <= low + 20) {
      return OvernightPhenotype.downwardPreBed;
    }
    if (cv > _cvTarget) return OvernightPhenotype.highVariability;

    final dinnerWasLateAndClose =
        dinner != null &&
        dinnerToBedMinutes != null &&
        dinnerToBedMinutes >= 0 &&
        dinnerToBedMinutes <= 180;
    if (dinnerWasLateAndClose) {
      final earlyNightMean = _windowMean(
        overnight,
        bedtime,
        bedtime.add(const Duration(hours: 3)),
      );
      if (earlyNightMean != null && earlyNightMean > high) {
        return OvernightPhenotype.lateDinnerHyperglycemia;
      }
    }

    return OvernightPhenotype.steady;
  }

  /// Counts distinct dips below [low] that persist for at least 15 minutes.
  int _countLowEvents(List<GlucoseReading> overnight, double low) {
    var events = 0;
    DateTime? runStart;
    for (final reading in overnight) {
      if (reading.valueMgDl < low) {
        runStart ??= reading.timestamp;
        if (reading.timestamp.difference(runStart).inMinutes >= 15) {
          events++;
          runStart = reading.timestamp.add(const Duration(days: 1)); // don't re-count this run
        }
      } else {
        runStart = null;
      }
    }
    return events;
  }

  GlucoseTrend _bedtimeTrend(List<GlucoseReading> readings, DateTime bedtime) {
    final window = readings
        .where(
          (reading) =>
              !reading.timestamp.isBefore(
                bedtime.subtract(const Duration(minutes: 60)),
              ) &&
              !reading.timestamp.isAfter(
                bedtime.add(const Duration(minutes: 30)),
              ),
        )
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (window.length < 2) return GlucoseTrend.flat;
    final delta = window.last.valueMgDl - window.first.valueMgDl;
    if (delta <= -15) return GlucoseTrend.falling;
    if (delta >= 15) return GlucoseTrend.rising;
    return GlucoseTrend.flat;
  }

  /// The reading closest to bedtime within [bedtime - 1h, bedtime + 30m] —
  /// a proxy for "where your glucose sat as you went to bed."
  double? _preBedMgDl(List<GlucoseReading> readings, DateTime bedtime) {
    GlucoseReading? nearest;
    var nearestGap = const Duration(days: 1);
    for (final reading in readings) {
      if (reading.timestamp.isBefore(bedtime.subtract(const Duration(minutes: 60))) ||
          reading.timestamp.isAfter(bedtime.add(const Duration(minutes: 30)))) {
        continue;
      }
      final gap = reading.timestamp.difference(bedtime).abs();
      if (gap < nearestGap) {
        nearestGap = gap;
        nearest = reading;
      }
    }
    return nearest?.valueMgDl;
  }

  double? _windowMean(
    List<GlucoseReading> readings,
    DateTime start,
    DateTime end,
  ) {
    final values = readings
        .where(
          (reading) =>
              !reading.timestamp.isBefore(start) &&
              !reading.timestamp.isAfter(end),
        )
        .map((reading) => reading.valueMgDl)
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _standardDeviation(List<double> values, double mean) {
    final variance =
        values.map((value) => pow(value - mean, 2)).reduce((a, b) => a + b) /
        values.length;
    return sqrt(variance).toDouble();
  }
}

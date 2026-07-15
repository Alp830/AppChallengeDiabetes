import 'dart:math';

import '../../cgm/models/glucose_models.dart';
import '../models/meal_models.dart';

class MealFingerprint {
  const MealFingerprint({
    required this.meal,
    required this.hasCoverage,
    this.baselineMgDl,
    this.peakMgDl,
    this.riseMgDl,
    this.minutesToPeak,
    this.minutesToRecovery,
    this.delayedRise = false,
    this.minutesInRange,
    this.minutesAboveRange,
    this.minutesBelowRange,
  });

  final MealEvent meal;
  final bool hasCoverage;
  final double? baselineMgDl;
  final double? peakMgDl;
  final double? riseMgDl;
  final int? minutesToPeak;
  final int? minutesToRecovery;
  final bool delayedRise;
  final int? minutesInRange;
  final int? minutesAboveRange;
  final int? minutesBelowRange;
}

class MealAnalysisService {
  const MealAnalysisService();

  MealFingerprint fingerprint(
    MealEvent meal,
    List<GlucoseReading> allReadings, {
    DateTime? nextMealAt,
    GlucoseSettings settings = const GlucoseSettings(),
  }) {
    final start = meal.timestamp.subtract(const Duration(minutes: 15));
    final maximumEnd = meal.timestamp.add(const Duration(hours: 4));
    final end = nextMealAt != null && nextMealAt.isBefore(maximumEnd)
        ? nextMealAt
        : maximumEnd;
    final baselineReadings = allReadings
        .where(
          (reading) =>
              !reading.timestamp.isBefore(start) &&
              !reading.timestamp.isAfter(meal.timestamp),
        )
        .map((reading) => reading.valueMgDl)
        .toList();
    final response = allReadings
        .where(
          (reading) =>
              !reading.timestamp.isBefore(meal.timestamp) &&
              reading.timestamp.isBefore(end),
        )
        .toList();
    if (baselineReadings.isEmpty || response.length < 3) {
      return MealFingerprint(meal: meal, hasCoverage: false);
    }
    final baseline = _median(baselineReadings);
    final peak = response.reduce(
      (a, b) => a.valueMgDl >= b.valueMgDl ? a : b,
    );
    int? recoveryMinutes;
    for (var index = 1; index < response.length; index++) {
      final previousNear = (response[index - 1].valueMgDl - baseline).abs() <=
          baseline * .10;
      final currentNear =
          (response[index].valueMgDl - baseline).abs() <= baseline * .10;
      if (previousNear && currentNear && response[index].timestamp.isAfter(peak.timestamp)) {
        recoveryMinutes = response[index]
            .timestamp
            .difference(meal.timestamp)
            .inMinutes;
        break;
      }
    }
    var inRange = 0;
    var above = 0;
    var below = 0;
    for (var index = 1; index < response.length; index++) {
      final minutes = response[index]
          .timestamp
          .difference(response[index - 1].timestamp)
          .inMinutes
          .clamp(0, 30);
      final value = response[index - 1].valueMgDl;
      if (value < settings.lowMgDl) {
        below += minutes;
      } else if (value > settings.highMgDl) {
        above += minutes;
      } else {
        inRange += minutes;
      }
    }
    final minutesToPeak = peak.timestamp.difference(meal.timestamp).inMinutes;
    return MealFingerprint(
      meal: meal,
      hasCoverage: true,
      baselineMgDl: baseline,
      peakMgDl: peak.valueMgDl,
      riseMgDl: peak.valueMgDl - baseline,
      minutesToPeak: minutesToPeak,
      minutesToRecovery: recoveryMinutes,
      delayedRise: minutesToPeak > 120,
      minutesInRange: settings.rangeConfirmed ? inRange : null,
      minutesAboveRange: settings.rangeConfirmed ? above : null,
      minutesBelowRange: settings.rangeConfirmed ? below : null,
    );
  }

  String evidenceLevel(int count) => count >= 6
      ? 'Repeated'
      : count >= 3
      ? 'Developing'
      : 'Preliminary';

  double consistency(List<MealFingerprint> fingerprints) {
    final rises = fingerprints
        .where((item) => item.riseMgDl != null)
        .map((item) => item.riseMgDl!)
        .toList();
    if (rises.length < 2) return 0;
    final average = rises.reduce((a, b) => a + b) / rises.length;
    final variance = rises
            .map((value) => pow(value - average, 2))
            .reduce((a, b) => a + b) /
        rises.length;
    return sqrt(variance).toDouble();
  }
}

double _median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

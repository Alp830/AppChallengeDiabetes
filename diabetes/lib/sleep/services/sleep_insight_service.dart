import 'dart:math';

import '../models/sleep_models.dart';

class SleepInsight {
  const SleepInsight({required this.title, required this.message});

  final String title;
  final String message;
}

/// Turns a run of [SleepLog]s (and optional next-morning fasting glucose) into
/// gentle, plain-language observations. Mirrors WorkoutInsightService.
class SleepInsightService {
  const SleepInsightService();

  /// Lower end of the report's 7–9h "sweet spot", in minutes.
  static const int _sweetSpotLowMinutes = 7 * 60;
  static const int _sweetSpotHighMinutes = 9 * 60;

  /// [morningFastingByDateId] maps a night's [SleepLog.dateId] to the first
  /// fasting glucose (mg/dL) after wake, when available.
  List<SleepInsight> buildInsights(
    List<SleepLog> logs, {
    Map<String, double> morningFastingByDateId = const {},
  }) {
    if (logs.length < 3) return const [];

    final recent = logs.take(14).toList();
    final insights = <SleepInsight>[];

    // Average duration + 7–9h framing.
    final averageMinutes =
        recent.map((log) => log.durationMinutes).reduce((a, b) => a + b) ~/
        recent.length;
    insights.add(
      SleepInsight(
        title: 'Your recent sleep',
        message:
            'Your last ${recent.length} nights averaged ${_hm(averageMinutes)}. '
            '${_sweetSpotNote(averageMinutes)}',
      ),
    );

    // Regularity of bedtime.
    final bedtimeMinutes = recent.map((log) => _nightMinute(log.bedtime)).toList();
    final spread = _standardDeviation(bedtimeMinutes);
    insights.add(
      SleepInsight(
        title: 'Bedtime consistency',
        message: spread <= 45
            ? 'Your bedtime has been steady lately — consistent sleep timing tends to support steadier glucose.'
            : spread <= 75
            ? 'Your bedtime moves around a little. Nudging it toward the same time can help your overnight rhythm.'
            : 'Your bedtime has varied a lot recently. A more consistent bedtime is one of the strongest levers for overnight glucose — no pressure, just something to aim for.',
      ),
    );

    // Morning link (S5): compare fasting glucose after longer vs shorter nights.
    final paired = recent
        .where((log) => morningFastingByDateId.containsKey(log.dateId))
        .toList();
    if (paired.length >= 3) {
      final longer = paired
          .where((log) => log.durationMinutes >= _sweetSpotLowMinutes)
          .map((log) => morningFastingByDateId[log.dateId]!)
          .toList();
      final shorter = paired
          .where((log) => log.durationMinutes < _sweetSpotLowMinutes)
          .map((log) => morningFastingByDateId[log.dateId]!)
          .toList();
      if (longer.isNotEmpty && shorter.isNotEmpty) {
        final longAvg = longer.reduce((a, b) => a + b) / longer.length;
        final shortAvg = shorter.reduce((a, b) => a + b) / shorter.length;
        final difference = (shortAvg - longAvg).round();
        if (difference.abs() >= 5) {
          insights.add(
            SleepInsight(
              title: 'Sleep and your mornings',
              message: difference > 0
                  ? 'Across ${paired.length} nights, your fasting glucose ran about $difference mg/dL higher after shorter nights. This is an observation, not a prediction.'
                  : 'Across ${paired.length} nights, your fasting glucose looked similar regardless of sleep length so far.',
            ),
          );
        }
      }
    }

    return insights.take(3).toList();
  }

  String evidenceLevel(int count) => count >= 6
      ? 'Repeated'
      : count >= 3
      ? 'Developing'
      : 'Preliminary';

  String _sweetSpotNote(int minutes) {
    if (minutes < _sweetSpotLowMinutes) {
      return 'That is under the 7–9 hour range linked with steadier glucose.';
    }
    if (minutes > _sweetSpotHighMinutes) {
      return 'That is a little over the 7–9 hour range — both short and long nights can matter.';
    }
    return 'That sits nicely in the 7–9 hour range linked with steadier glucose.';
  }

  /// Minutes-of-day for a bedtime, shifted so evening and after-midnight
  /// bedtimes cluster together instead of wrapping around midnight.
  int _nightMinute(DateTime time) {
    final minute = time.hour * 60 + time.minute;
    return minute < 12 * 60 ? minute + 24 * 60 : minute;
  }

  double _standardDeviation(List<int> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((value) => pow(value - mean, 2)).reduce((a, b) => a + b) /
        values.length;
    return sqrt(variance).toDouble();
  }

  String _hm(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours == 0) return '${mins}m';
    return mins == 0 ? '${hours}h' : '${hours}h ${mins}m';
  }
}

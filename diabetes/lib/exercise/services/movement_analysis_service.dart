import '../../cgm/models/glucose_models.dart';
import '../models/workout_session.dart';

class WorkoutResponse {
  const WorkoutResponse({
    required this.session,
    required this.hasCoverage,
    this.baselineMgDl,
    this.endingMgDl,
    this.twoHourMgDl,
    this.overnightAverageMgDl,
  });
  final WorkoutSession session;
  final bool hasCoverage;
  final double? baselineMgDl;
  final double? endingMgDl;
  final double? twoHourMgDl;
  final double? overnightAverageMgDl;

  double? get duringChange =>
      baselineMgDl == null || endingMgDl == null ? null : endingMgDl! - baselineMgDl!;
  double? get twoHourChange =>
      baselineMgDl == null || twoHourMgDl == null ? null : twoHourMgDl! - baselineMgDl!;
}

class MovementAnalysisService {
  const MovementAnalysisService();

  WorkoutResponse response(WorkoutSession session, List<GlucoseReading> readings) {
    final baseline = _values(
      readings,
      session.startedAt.subtract(const Duration(minutes: 15)),
      session.startedAt,
    );
    final ending = _nearest(readings, session.completedAt, const Duration(minutes: 20));
    final twoHour = _nearest(
      readings,
      session.completedAt.add(const Duration(hours: 2)),
      const Duration(minutes: 30),
    );
    double? overnight;
    if (session.completedAt.hour >= 18) {
      final nextDay = DateTime(
        session.completedAt.year,
        session.completedAt.month,
        session.completedAt.day + 1,
      );
      final values = _values(readings, nextDay, nextDay.add(const Duration(hours: 6)));
      if (values.isNotEmpty) overnight = values.reduce((a, b) => a + b) / values.length;
    }
    if (baseline.isEmpty || ending == null) {
      return WorkoutResponse(session: session, hasCoverage: false);
    }
    return WorkoutResponse(
      session: session,
      hasCoverage: true,
      baselineMgDl: _median(baseline),
      endingMgDl: ending.valueMgDl,
      twoHourMgDl: twoHour?.valueMgDl,
      overnightAverageMgDl: overnight,
    );
  }

  String evidenceLevel(int count) => count >= 6
      ? 'Repeated'
      : count >= 3
      ? 'Developing'
      : 'Preliminary';
}

List<double> _values(List<GlucoseReading> readings, DateTime start, DateTime end) => readings
    .where((item) => !item.timestamp.isBefore(start) && !item.timestamp.isAfter(end))
    .map((item) => item.valueMgDl)
    .toList();

GlucoseReading? _nearest(
  List<GlucoseReading> readings,
  DateTime target,
  Duration tolerance,
) {
  GlucoseReading? nearest;
  var difference = tolerance + const Duration(seconds: 1);
  for (final reading in readings) {
    final current = reading.timestamp.difference(target).abs();
    if (current <= tolerance && current < difference) {
      nearest = reading;
      difference = current;
    }
  }
  return nearest;
}

double _median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

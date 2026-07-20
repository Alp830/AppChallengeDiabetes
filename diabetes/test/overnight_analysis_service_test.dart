import 'package:diabetes/cgm/models/glucose_models.dart';
import 'package:diabetes/meals/models/meal_models.dart';
import 'package:diabetes/sleep/models/sleep_models.dart';
import 'package:diabetes/sleep/services/overnight_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _service = OvernightAnalysisService();
final _bedtime = DateTime(2026, 7, 13, 23);
final _wake = DateTime(2026, 7, 14, 7);

void main() {
  test('flat overnight glucose reads as a steady night', () {
    final readings = _series(_bedtime, _wake, (i, t) => 110);
    final analysis = _service.analyze(_log(), readings);

    expect(analysis.hasCoverage, isTrue);
    expect(analysis.phenotype, OvernightPhenotype.steady);
    expect(analysis.timeInRangePercent, closeTo(100, 0.1));
    expect(analysis.lowEventCount, 0);
  });

  test('wide swings read as a high-variability night', () {
    final readings = _series(_bedtime, _wake, (i, t) => i.isEven ? 100 : 260);
    final analysis = _service.analyze(_log(), readings);

    expect(analysis.cvPercent, greaterThan(36));
    expect(analysis.phenotype, OvernightPhenotype.highVariability);
  });

  test('repeated sustained dips read as frequent lows', () {
    final readings = _series(_bedtime, _wake, (i, t) {
      final hoursIn = t.difference(_bedtime).inMinutes / 60.0;
      final inFirstDip = hoursIn >= 2 && hoursIn < 2.75;
      final inSecondDip = hoursIn >= 5 && hoursIn < 5.75;
      return (inFirstDip || inSecondDip) ? 60 : 110;
    });
    final analysis = _service.analyze(_log(), readings);

    expect(analysis.lowEventCount, greaterThanOrEqualTo(2));
    expect(analysis.phenotype, OvernightPhenotype.frequentLows);
  });

  test('high early-night glucose after a late dinner is flagged', () {
    final readings = _series(_bedtime, _wake, (i, t) {
      final hoursIn = t.difference(_bedtime).inMinutes / 60.0;
      return hoursIn < 3 ? 210 : 120;
    });
    final dinner = _dinner(_bedtime.subtract(const Duration(minutes: 60)));
    final analysis = _service.analyze(_log(), readings, dinner: dinner);

    expect(analysis.phenotype, OvernightPhenotype.lateDinnerHyperglycemia);
    expect(analysis.dinnerToBedMinutes, 60);
  });

  test('too few readings reports no coverage', () {
    final analysis = _service.analyze(_log(), [_reading(_bedtime, 110)]);
    expect(analysis.hasCoverage, isFalse);
    expect(analysis.phenotype, OvernightPhenotype.insufficientData);
  });
}

SleepLog _log() => SleepLog(
  id: 'night',
  bedtime: _bedtime,
  wakeTime: _wake,
  quality: 3,
  wakeUps: 0,
);

List<GlucoseReading> _series(
  DateTime start,
  DateTime end,
  double Function(int index, DateTime time) value,
) {
  final readings = <GlucoseReading>[];
  var time = start;
  var index = 0;
  while (!time.isAfter(end)) {
    readings.add(_reading(time, value(index, time)));
    time = time.add(const Duration(minutes: 15));
    index++;
  }
  return readings;
}

GlucoseReading _reading(DateTime timestamp, double value) => GlucoseReading(
  id: timestamp.toIso8601String(),
  timestamp: timestamp,
  valueMgDl: value,
  originalValue: value,
  originalUnit: 'mg/dL',
  source: GlucoseSource.libreView,
  recordType: GlucoseRecordType.historic,
);

MealEvent _dinner(DateTime timestamp) => MealEvent(
  id: 'dinner',
  name: 'Dinner',
  timestamp: timestamp,
  mealType: 'Dinner',
  portion: MealPortion.usual,
  carbBand: CarbBand.high,
  mealOrder: MealOrder.together,
  preparation: MealPreparation.fresh,
);

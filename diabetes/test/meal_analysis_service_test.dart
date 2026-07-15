import 'package:diabetes/cgm/models/glucose_models.dart';
import 'package:diabetes/meals/models/meal_models.dart';
import 'package:diabetes/meals/services/meal_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mealTime = DateTime(2026, 7, 13, 12);
  const service = MealAnalysisService();

  test('builds a meal fingerprint and detects a delayed peak', () {
    final readings = <GlucoseReading>[
      _reading(mealTime.subtract(const Duration(minutes: 15)), 100),
      _reading(mealTime, 102),
      _reading(mealTime.add(const Duration(hours: 1)), 130),
      _reading(mealTime.add(const Duration(hours: 2)), 125),
      _reading(mealTime.add(const Duration(hours: 3)), 160),
      _reading(mealTime.add(const Duration(hours: 3, minutes: 30)), 105),
      _reading(mealTime.add(const Duration(hours: 3, minutes: 45)), 103),
    ];
    final result = service.fingerprint(
      _meal(mealTime),
      readings,
      settings: const GlucoseSettings(rangeConfirmed: true),
    );

    expect(result.hasCoverage, isTrue);
    expect(result.riseMgDl, closeTo(60, 1));
    expect(result.delayedRise, isTrue);
    expect(result.minutesToRecovery, isNotNull);
  });

  test('does not claim a fingerprint without enough coverage', () {
    final result = service.fingerprint(
      _meal(mealTime),
      [_reading(mealTime, 100)],
    );
    expect(result.hasCoverage, isFalse);
  });

  test('requires three events for developing evidence', () {
    expect(service.evidenceLevel(2), 'Preliminary');
    expect(service.evidenceLevel(3), 'Developing');
    expect(service.evidenceLevel(6), 'Repeated');
  });
}

MealEvent _meal(DateTime timestamp) => MealEvent(
  id: 'meal',
  name: 'Lunch',
  timestamp: timestamp,
  mealType: 'Lunch',
  portion: MealPortion.usual,
  carbBand: CarbBand.medium,
  mealOrder: MealOrder.together,
  preparation: MealPreparation.fresh,
);

GlucoseReading _reading(DateTime timestamp, double value) => GlucoseReading(
  id: timestamp.toIso8601String(),
  timestamp: timestamp,
  valueMgDl: value,
  originalValue: value,
  originalUnit: 'mg/dL',
  source: GlucoseSource.libreView,
  recordType: GlucoseRecordType.historic,
);

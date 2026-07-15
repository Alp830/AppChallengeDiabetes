import 'dart:math';

import '../models/glucose_models.dart';

class DemoCgmImporter implements CgmImporter {
  const DemoCgmImporter({this.days = 7});

  final int days;

  @override
  Future<CgmImportPreview> parse(String content) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final readings = <GlucoseReading>[];
    final random = Random(42);
    for (var index = 0; index < days * 96; index++) {
      final timestamp = start.add(Duration(minutes: index * 15));
      final hour = timestamp.hour + timestamp.minute / 60;
      final mealBump = [8.0, 13.0, 19.0]
          .map((meal) => 58 * exp(-pow((hour - meal) / 1.25, 2)))
          .fold<double>(0, (sum, value) => sum + value);
      final value = 105 + mealBump + sin(index / 9) * 8 + random.nextDouble() * 6;
      readings.add(
        GlucoseReading(
          id: 'demo-${timestamp.toUtc().microsecondsSinceEpoch}',
          timestamp: timestamp,
          valueMgDl: value,
          originalValue: value,
          originalUnit: 'mg/dL',
          source: GlucoseSource.demo,
          recordType: GlucoseRecordType.historic,
          deviceId: 'demo',
        ),
      );
    }
    return CgmImportPreview(
      source: GlucoseSource.demo,
      readings: readings,
      rejectedRows: 0,
      duplicateRows: 0,
      detectedUnit: 'mg/dL',
      timezoneWasInferred: true,
      deviceId: 'demo',
    );
  }
}

import 'package:diabetes/cgm/models/glucose_models.dart';
import 'package:diabetes/sleep/models/sleep_models.dart';
import 'package:diabetes/sleep/services/bedtime_advisor_service.dart';
import 'package:diabetes/sleep/services/overnight_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _advisor = BedtimeAdvisorService();
const _analysis = OvernightAnalysisService();

OvernightAnalysis _night({
  bool hasCoverage = true,
  double? lowest,
  double? timeBelow70,
  double? timeBelow54,
  int lowEventCount = 0,
  GlucoseTrend trend = GlucoseTrend.flat,
  double? preBed,
}) {
  return OvernightAnalysis(
    hasCoverage: hasCoverage,
    readingCount: 32,
    phenotype: OvernightPhenotype.steady,
    lowestMgDl: lowest,
    timeBelow70Percent: timeBelow70,
    timeBelow54Percent: timeBelow54,
    lowEventCount: lowEventCount,
    bedtimeTrend: trend,
    preBedMgDl: preBed,
  );
}

void main() {
  group('S8 nocturnal-low flag', () {
    test('severe when readings dip below 54', () {
      final advice = _advisor.evaluate(
        _night(lowest: 48, timeBelow70: 6, timeBelow54: 3, lowEventCount: 1),
      );
      expect(advice.nocturnalLow, isNotNull);
      expect(advice.nocturnalLow!.severity, NocturnalLowSeverity.severe);
    });

    test('mild when there are lows in the 54–70 band only', () {
      final advice = _advisor.evaluate(
        _night(lowest: 63, timeBelow70: 3, timeBelow54: 0, lowEventCount: 1),
      );
      expect(advice.nocturnalLow, isNotNull);
      expect(advice.nocturnalLow!.severity, NocturnalLowSeverity.mild);
    });

    test('no flag on a night that stayed in range', () {
      final advice = _advisor.evaluate(
        _night(lowest: 95, timeBelow70: 0, timeBelow54: 0),
      );
      expect(advice.nocturnalLow, isNull);
    });

    test('a brief dip still counts as at least one event', () {
      final advice = _advisor.evaluate(
        _night(lowest: 66, timeBelow70: 2, lowEventCount: 0),
      );
      expect(advice.nocturnalLow, isNotNull);
      expect(advice.nocturnalLow!.eventCount, 1);
    });
  });

  group('S7 bedtime-snack suggestion', () {
    test('suggests a snack when pre-bed is low-normal and drifting down', () {
      final advice = _advisor.evaluate(
        _night(preBed: 92, trend: GlucoseTrend.falling, lowest: 88),
      );
      expect(advice.snackSuggestion, isNotNull);
      expect(advice.snackSuggestion!.preBedMgDl, 92);
    });

    test('stays quiet when the pre-bed trend is flat', () {
      final advice = _advisor.evaluate(
        _night(preBed: 92, trend: GlucoseTrend.flat),
      );
      expect(advice.snackSuggestion, isNull);
    });

    test('stays quiet when pre-bed glucose is comfortably high', () {
      final advice = _advisor.evaluate(
        _night(preBed: 150, trend: GlucoseTrend.falling),
      );
      expect(advice.snackSuggestion, isNull);
    });

    test('stays quiet when glucose is already below the low mark', () {
      final advice = _advisor.evaluate(
        _night(preBed: 64, trend: GlucoseTrend.falling, lowest: 60),
      );
      expect(advice.snackSuggestion, isNull);
    });

    test('always carries a clinician note', () {
      expect(BedtimeSnackSuggestion.clinicianNote, contains('clinician'));
    });
  });

  test('no coverage yields no advice', () {
    final advice = _advisor.evaluate(_night(hasCoverage: false));
    expect(advice.hasAnything, isFalse);
  });

  test('analysis feeds pre-bed value and downward trend into the snack rule', () {
    final bedtime = DateTime(2026, 7, 13, 23);
    final wake = DateTime(2026, 7, 14, 7);
    final readings = <GlucoseReading>[];
    var time = bedtime.subtract(const Duration(hours: 1));
    var index = 0;
    while (!time.isAfter(wake)) {
      // High an hour before bed, gliding down into low-normal by bedtime,
      // then holding steady overnight.
      final minutesFromBed = time.difference(bedtime).inMinutes;
      final double value;
      if (minutesFromBed <= 0) {
        value = (95 - minutesFromBed / 60 * 25).clamp(90, 130).toDouble();
      } else {
        value = 92;
      }
      readings.add(
        GlucoseReading(
          id: '$index',
          timestamp: time,
          valueMgDl: value,
          originalValue: value,
          originalUnit: 'mg/dL',
          source: GlucoseSource.libreView,
          recordType: GlucoseRecordType.historic,
        ),
      );
      time = time.add(const Duration(minutes: 15));
      index++;
    }

    final result = _analysis.analyze(
      SleepLog(
        id: 'n',
        bedtime: bedtime,
        wakeTime: wake,
        quality: 3,
        wakeUps: 0,
      ),
      readings,
    );

    expect(result.preBedMgDl, isNotNull);
    expect(result.bedtimeTrend, GlucoseTrend.falling);

    final advice = _advisor.evaluate(result);
    expect(advice.snackSuggestion, isNotNull);
  });
}

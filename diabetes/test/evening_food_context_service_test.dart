import 'package:diabetes/sleep/services/evening_food_context_service.dart';
import 'package:diabetes/sleep/services/overnight_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a no-signal summary produces no prompt context', () {
    const summary = OvernightPhenotypeSummary.none;

    expect(summary.hasSignal, isFalse);
    expect(summary.promptContext, isEmpty);
  });

  test('a single night is not enough signal to tailor the agent', () {
    const summary = OvernightPhenotypeSummary(
      nightsAnalyzed: 1,
      dominant: OvernightPhenotype.lateDinnerHyperglycemia,
      recurringLateDinnerHighs: false,
      recurringLows: false,
    );

    expect(summary.hasSignal, isFalse);
    expect(summary.promptContext, isEmpty);
  });

  test('a recurring pattern surfaces the dominant phenotype softly', () {
    const summary = OvernightPhenotypeSummary(
      nightsAnalyzed: 5,
      dominant: OvernightPhenotype.lateDinnerHyperglycemia,
      recurringLateDinnerHighs: true,
      recurringLows: false,
    );

    expect(summary.hasSignal, isTrue);
    expect(summary.promptContext, contains('5 nights'));
    expect(
      summary.promptContext,
      contains(OvernightPhenotype.lateDinnerHyperglycemia.label),
    );
    // No diagnosis / alarm language.
    expect(summary.promptContext.toLowerCase(), isNot(contains('diagnos')));
  });

  test('recurring lows add a do-not-push-low-carb caveat', () {
    const summary = OvernightPhenotypeSummary(
      nightsAnalyzed: 4,
      dominant: OvernightPhenotype.steady,
      recurringLateDinnerHighs: false,
      recurringLows: true,
    );

    expect(summary.hasSignal, isTrue);
    expect(summary.promptContext, contains('low-carb'));
  });

  test('a caveat is not repeated when it is already the dominant pattern', () {
    const summary = OvernightPhenotypeSummary(
      nightsAnalyzed: 6,
      dominant: OvernightPhenotype.frequentLows,
      recurringLateDinnerHighs: false,
      recurringLows: true,
    );

    // The dominant summary already speaks to lows; no redundant caveat sentence.
    expect(summary.promptContext, isNot(contains('low-carb evening meals')));
  });
}

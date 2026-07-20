import 'package:diabetes/meals/models/meal_balance_models.dart';
import 'package:diabetes/meals/models/meal_models.dart';
import 'package:diabetes/meals/services/meal_balance_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calculator = MealBalanceCalculator();

  test(
    'a meal at every full-credit anchor scores 100 with high confidence',
    () {
      final result = calculator.calculate(
        const MealBalanceInput(
          proteinGrams: 25,
          fiberGrams: 8,
          produceCupEquivalents: 1.5,
          hydrationMilliliters: 250,
          producePlatePercent: 50,
          proteinPlatePercent: 25,
          qualityCarbPlatePercent: 25,
        ),
      )!;

      expect(result.overallScore, closeTo(100, 0.001));
      expect(result.confidence, MealBalanceConfidence.high);
      expect(result.componentScores.values, everyElement(100));
    },
  );

  test('protein and fiber use continuous capped thresholds', () {
    final result = calculator.calculate(
      const MealBalanceInput(proteinGrams: 17.5, fiberGrams: 5),
    )!;

    expect(result.componentScores[MealBalanceComponent.protein], 50);
    expect(result.componentScores[MealBalanceComponent.fiber], 50);
    expect(result.confidence, MealBalanceConfidence.low);

    final capped = calculator.calculate(
      const MealBalanceInput(proteinGrams: 80, fiberGrams: 20),
    )!;
    expect(capped.componentScores.values, everyElement(100));
    expect(capped.fiberStretch, isTrue);
  });

  test('missing values renormalize while explicit zero receives zero', () {
    final missingHydration = calculator.calculate(
      const MealBalanceInput(
        proteinGrams: 25,
        fiberGrams: 8,
        produceCupEquivalents: 1.5,
      ),
    )!;
    expect(missingHydration.overallScore, 100);
    expect(missingHydration.confidence, MealBalanceConfidence.medium);

    final explicitZero = calculator.calculate(
      const MealBalanceInput(hydrationMilliliters: 0),
    )!;
    expect(explicitZero.overallScore, 0);
    expect(explicitZero.confidence, MealBalanceConfidence.low);
  });

  test('portion balance uses normalized total-variation distance', () {
    final target = calculator.calculate(
      const MealBalanceInput(
        producePlatePercent: 50,
        proteinPlatePercent: 25,
        qualityCarbPlatePercent: 25,
      ),
    )!;
    expect(
      target.componentScores[MealBalanceComponent.portionBalance],
      closeTo(100, 0.001),
    );

    final maximumDeviation = calculator.calculate(
      const MealBalanceInput(
        producePlatePercent: 0,
        proteinPlatePercent: 100,
        qualityCarbPlatePercent: 0,
      ),
    )!;
    expect(
      maximumDeviation.componentScores[MealBalanceComponent.portionBalance],
      closeTo(0, 0.001),
    );
  });

  test('no observed components produces no result', () {
    expect(calculator.calculate(const MealBalanceInput()), isNull);
  });

  test('input round-trips through the nested Firestore representation', () {
    const input = MealBalanceInput(
      proteinGrams: 24,
      fiberGrams: 10,
      produceCupEquivalents: 1.25,
      hydrationMilliliters: 350,
      producePlatePercent: 45,
      proteinPlatePercent: 30,
      qualityCarbPlatePercent: 25,
    );

    final decoded = MealBalanceInput.fromFirestore(input.toFirestore());
    expect(decoded.proteinGrams, input.proteinGrams);
    expect(decoded.fiberGrams, input.fiberGrams);
    expect(decoded.produceCupEquivalents, input.produceCupEquivalents);
    expect(decoded.hydrationMilliliters, input.hydrationMilliliters);
    expect(decoded.plateTotal, 100);
  });

  test('meal and template parsing remain compatible with legacy data', () {
    final legacy = MealEvent.fromFirestore('legacy', {'name': 'Old meal'});
    expect(legacy.balanceInput, isNull);

    final current = MealEvent.fromFirestore('current', {
      'name': 'Balanced meal',
      'mealBalance': const MealBalanceInput(
        proteinGrams: 25,
        fiberGrams: 8,
      ).toFirestore(),
    });
    expect(current.balanceInput?.proteinGrams, 25);
    expect(current.toFirestore()['mealBalance'], isA<Map<String, dynamic>>());

    final template = MealTemplate.fromFirestore('template', {
      'name': 'Repeat meal',
      'mealBalance': const MealBalanceInput(
        hydrationMilliliters: 300,
      ).toFirestore(),
    });
    expect(template.balanceInput?.hydrationMilliliters, 300);
  });
}

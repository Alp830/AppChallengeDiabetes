import '../models/meal_balance_models.dart';

class MealBalanceCalculator {
  const MealBalanceCalculator();

  MealBalanceResult? calculate(MealBalanceInput input) {
    final scores = <MealBalanceComponent, double>{};

    if (input.proteinGrams case final grams?) {
      scores[MealBalanceComponent.protein] = _percentage((grams - 10) / 15);
    }
    if (input.fiberGrams case final grams?) {
      scores[MealBalanceComponent.fiber] = _percentage((grams - 2) / 6);
    }

    final produceCandidates = <double>[];
    if (input.produceCupEquivalents case final cups?) {
      produceCandidates.add(cups / 1.5);
    }
    if (input.producePlatePercent case final percent?) {
      produceCandidates.add(percent / 50);
    }
    if (produceCandidates.isNotEmpty) {
      scores[MealBalanceComponent.produce] = _percentage(
        produceCandidates.reduce((a, b) => a > b ? a : b),
      );
    }

    if (input.hydrationMilliliters case final milliliters?) {
      scores[MealBalanceComponent.hydration] = _percentage(milliliters / 250);
    }

    final portionScore = _portionScore(input);
    if (portionScore != null) {
      scores[MealBalanceComponent.portionBalance] = portionScore;
    }

    if (scores.isEmpty) return null;

    final availableWeight = scores.keys.fold<double>(
      0,
      (sum, component) => sum + component.weight,
    );
    final contributions = <MealBalanceComponent, double>{
      for (final entry in scores.entries)
        entry.key: entry.value * entry.key.weight / availableWeight,
    };
    final overall = contributions.values.fold<double>(0, (a, b) => a + b);
    final confidence = scores.length == MealBalanceComponent.values.length
        ? MealBalanceConfidence.high
        : scores.length >= 3
        ? MealBalanceConfidence.medium
        : MealBalanceConfidence.low;

    final ranked = scores.entries.toList()
      ..sort((a, b) {
        final scoreOrder = b.value.compareTo(a.value);
        return scoreOrder != 0
            ? scoreOrder
            : a.key.index.compareTo(b.key.index);
      });
    final strongest = ranked.first.key;
    final weakest = ranked.last.key;

    return MealBalanceResult(
      overallScore: overall,
      componentScores: Map.unmodifiable(scores),
      weightedContributions: Map.unmodifiable(contributions),
      confidence: confidence,
      fiberStretch: (input.fiberGrams ?? 0) >= 10,
      whatsWorking: _strengthMessage(strongest),
      optionalImprovement: overall >= 90
          ? 'You may not need a change here - repeating this structure is already a strong move.'
          : _improvementMessage(weakest),
    );
  }

  double? _portionScore(MealBalanceInput input) {
    if (!input.hasCompletePlateSplit) return null;
    final total = input.plateTotal!;
    if (total <= 0) return 0;

    final produce = input.producePlatePercent! / total;
    final protein = input.proteinPlatePercent! / total;
    final qualityCarb = input.qualityCarbPlatePercent! / total;
    final totalVariation =
        0.5 *
        ((produce - 0.50).abs() +
            (protein - 0.25).abs() +
            (qualityCarb - 0.25).abs());
    return _percentage(1 - (totalVariation / 0.75));
  }

  double _percentage(double fraction) =>
      (fraction.clamp(0.0, 1.0) * 100).toDouble();

  String _strengthMessage(
    MealBalanceComponent component,
  ) => switch (component) {
    MealBalanceComponent.protein =>
      'This meal has a solid protein anchor, which can help it feel more filling.',
    MealBalanceComponent.fiber =>
      'Fiber is doing useful work here and can support fullness and meal quality.',
    MealBalanceComponent.produce =>
      'This meal has a good produce base, supporting volume and variety.',
    MealBalanceComponent.hydration =>
      'You included a helpful unsweetened drink with or near this meal.',
    MealBalanceComponent.portionBalance =>
      'The portions are well distributed across produce, protein, and quality carbohydrates.',
  };

  String _improvementMessage(
    MealBalanceComponent component,
  ) => switch (component) {
    MealBalanceComponent.protein =>
      'If you want more staying power, add a little protein such as yogurt, tofu, eggs, fish, or beans.',
    MealBalanceComponent.fiber =>
      'If you want more fiber, try beans, lentils, berries, vegetables, or a whole-grain side.',
    MealBalanceComponent.produce =>
      'To round it out, add vegetables or fruit if that fits the meal.',
    MealBalanceComponent.hydration =>
      'An easy addition would be water or an unsweetened drink with the meal.',
    MealBalanceComponent.portionBalance =>
      'If you want a more balanced plate, move a little space toward produce while keeping protein and quality carbohydrates represented.',
  };
}

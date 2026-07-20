enum MealBalanceComponent {
  protein('Protein', 0.20),
  fiber('Fiber', 0.25),
  produce('Produce', 0.20),
  hydration('Hydration', 0.10),
  portionBalance('Portion balance', 0.25);

  const MealBalanceComponent(this.label, this.weight);

  final String label;
  final double weight;
}

enum MealBalanceConfidence {
  low('Low'),
  medium('Medium'),
  high('High');

  const MealBalanceConfidence(this.label);

  final String label;
}

class MealBalanceInput {
  const MealBalanceInput({
    this.proteinGrams,
    this.fiberGrams,
    this.produceCupEquivalents,
    this.hydrationMilliliters,
    this.producePlatePercent,
    this.proteinPlatePercent,
    this.qualityCarbPlatePercent,
  });

  final double? proteinGrams;
  final double? fiberGrams;
  final double? produceCupEquivalents;
  final double? hydrationMilliliters;
  final double? producePlatePercent;
  final double? proteinPlatePercent;
  final double? qualityCarbPlatePercent;

  bool get isEmpty =>
      proteinGrams == null &&
      fiberGrams == null &&
      produceCupEquivalents == null &&
      hydrationMilliliters == null &&
      producePlatePercent == null &&
      proteinPlatePercent == null &&
      qualityCarbPlatePercent == null;

  bool get hasCompletePlateSplit =>
      producePlatePercent != null &&
      proteinPlatePercent != null &&
      qualityCarbPlatePercent != null;

  double? get plateTotal => !hasCompletePlateSplit
      ? null
      : producePlatePercent! + proteinPlatePercent! + qualityCarbPlatePercent!;

  Map<String, dynamic> toFirestore() => {
    'schemaVersion': 1,
    if (proteinGrams != null) 'proteinGrams': proteinGrams,
    if (fiberGrams != null) 'fiberGrams': fiberGrams,
    if (produceCupEquivalents != null)
      'produceCupEquivalents': produceCupEquivalents,
    if (hydrationMilliliters != null)
      'hydrationMilliliters': hydrationMilliliters,
    if (producePlatePercent != null) 'producePlatePercent': producePlatePercent,
    if (proteinPlatePercent != null) 'proteinPlatePercent': proteinPlatePercent,
    if (qualityCarbPlatePercent != null)
      'qualityCarbPlatePercent': qualityCarbPlatePercent,
  };

  factory MealBalanceInput.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return const MealBalanceInput();
    return MealBalanceInput(
      proteinGrams: (data['proteinGrams'] as num?)?.toDouble(),
      fiberGrams: (data['fiberGrams'] as num?)?.toDouble(),
      produceCupEquivalents: (data['produceCupEquivalents'] as num?)
          ?.toDouble(),
      hydrationMilliliters: (data['hydrationMilliliters'] as num?)?.toDouble(),
      producePlatePercent: (data['producePlatePercent'] as num?)?.toDouble(),
      proteinPlatePercent: (data['proteinPlatePercent'] as num?)?.toDouble(),
      qualityCarbPlatePercent: (data['qualityCarbPlatePercent'] as num?)
          ?.toDouble(),
    );
  }
}

class MealBalanceResult {
  const MealBalanceResult({
    required this.overallScore,
    required this.componentScores,
    required this.weightedContributions,
    required this.confidence,
    required this.fiberStretch,
    required this.whatsWorking,
    required this.optionalImprovement,
  });

  final double overallScore;
  final Map<MealBalanceComponent, double> componentScores;
  final Map<MealBalanceComponent, double> weightedContributions;
  final MealBalanceConfidence confidence;
  final bool fiberStretch;
  final String whatsWorking;
  final String optionalImprovement;
}

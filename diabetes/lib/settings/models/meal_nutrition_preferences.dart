/// Saved per-account nutrient priorities that steer meal recommendations.
class MealNutritionPreferences {
  const MealNutritionPreferences({
    this.highProtein = false,
    this.highCarbs = false,
    this.highFiber = false,
  });

  static const none = MealNutritionPreferences();

  /// Stable identifiers, later reused as `unmetNutritionPreferences` values.
  static const proteinKey = 'protein';
  static const carbsKey = 'carbs';
  static const fiberKey = 'fiber';

  static const proteinLabel = 'High protein';
  static const carbsLabel = 'High carbs';
  static const fiberLabel = 'High fiber';

  final bool highProtein;
  final bool highCarbs;
  final bool highFiber;

  bool get hasAny => highProtein || highCarbs || highFiber;

  /// Selected keys in fixed order: protein, carbs, fiber.
  List<String> get selectedKeys => [
    if (highProtein) proteinKey,
    if (highCarbs) carbsKey,
    if (highFiber) fiberKey,
  ];

  /// Selected labels in fixed order: protein, carbs, fiber.
  List<String> get selectedLabels => [
    if (highProtein) proteinLabel,
    if (highCarbs) carbsLabel,
    if (highFiber) fiberLabel,
  ];

  factory MealNutritionPreferences.fromMap(Object? data) {
    if (data is! Map) return none;
    return MealNutritionPreferences(
      highProtein: data['highProtein'] == true,
      highCarbs: data['highCarbs'] == true,
      highFiber: data['highFiber'] == true,
    );
  }

  Map<String, bool> toMap() => {
    'highProtein': highProtein,
    'highCarbs': highCarbs,
    'highFiber': highFiber,
  };

  MealNutritionPreferences copyWith({
    bool? highProtein,
    bool? highCarbs,
    bool? highFiber,
  }) => MealNutritionPreferences(
    highProtein: highProtein ?? this.highProtein,
    highCarbs: highCarbs ?? this.highCarbs,
    highFiber: highFiber ?? this.highFiber,
  );

  @override
  bool operator ==(Object other) =>
      other is MealNutritionPreferences &&
      other.highProtein == highProtein &&
      other.highCarbs == highCarbs &&
      other.highFiber == highFiber;

  @override
  int get hashCode => Object.hash(highProtein, highCarbs, highFiber);
}

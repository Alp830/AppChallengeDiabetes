import '../../settings/models/meal_nutrition_preferences.dart';

/// How many meals go in each fallback group when the per-serving budget and
/// the selected nutrition priorities cannot all be met together.
class FallbackSplit {
  const FallbackSplit({
    required this.nutritionFirst,
    required this.budgetFirst,
  });

  final int nutritionFirst;
  final int budgetFirst;

  @override
  bool operator ==(Object other) =>
      other is FallbackSplit &&
      other.nutritionFirst == nutritionFirst &&
      other.budgetFirst == budgetFirst;

  @override
  int get hashCode => Object.hash(nutritionFirst, budgetFirst);

  @override
  String toString() =>
      'FallbackSplit(nutritionFirst: $nutritionFirst, budgetFirst: $budgetFirst)';
}

/// The approved split: one meal is always budget-first; otherwise the
/// nutrition-first group gets the smaller half (1→0/1, 2→1/1, 3→1/2, 4→2/2,
/// 5→2/3).
FallbackSplit fallbackSplit(int n) {
  if (n < 1) throw ArgumentError.value(n, 'n', 'must be at least 1');
  if (n == 1) return const FallbackSplit(nutritionFirst: 0, budgetFirst: 1);
  final nutritionFirst = n ~/ 2;
  return FallbackSplit(
    nutritionFirst: nutritionFirst,
    budgetFirst: n - nutritionFirst,
  );
}

const priorityModeAllPreferences = 'allPreferences';
const priorityModeNutritionFirst = 'nutritionFirst';
const priorityModeBudgetFirst = 'budgetFirst';

const _validModes = {
  priorityModeAllPreferences,
  priorityModeNutritionFirst,
  priorityModeBudgetFirst,
};

/// The slice of a parsed meal the response check needs, kept apart from
/// `MealRecommendation` so the rules stay pure and testable.
class MealPriorityData {
  const MealPriorityData({
    this.priorityMode,
    this.unmetNutritionPreferences = const [],
    this.constraintNotice,
    this.estimatedCostUpperBoundPerServing,
  });

  final String? priorityMode;
  final List<String> unmetNutritionPreferences;
  final String? constraintNotice;
  final double? estimatedCostUpperBoundPerServing;

  bool get _hasNotice => (constraintNotice?.trim().isNotEmpty) ?? false;
  bool get _isFallback =>
      priorityMode == priorityModeNutritionFirst ||
      priorityMode == priorityModeBudgetFirst;
}

/// Throws [FormatException] when a model answer does not follow the request,
/// so the existing bounded retry asks again instead of showing it.
void validateMealResponse(
  List<MealPriorityData> meals, {
  required int requestedCount,
  required MealNutritionPreferences preferences,
  double? budgetPerServing,
}) {
  if (meals.isEmpty) {
    throw const FormatException('Gemini returned no meals');
  }
  if (meals.length != requestedCount) {
    throw FormatException(
      'Gemini returned ${meals.length} meals, expected $requestedCount',
    );
  }

  final budget = budgetPerServing;
  final selected = preferences.selectedKeys;
  final active = preferences.hasAny;

  for (final meal in meals) {
    final mode = meal.priorityMode;
    if (mode != null && !_validModes.contains(mode)) {
      throw FormatException('Invalid priorityMode "$mode"');
    }
    final bound = meal.estimatedCostUpperBoundPerServing;
    if (bound != null && (!bound.isFinite || bound < 0)) {
      throw FormatException(
        'Invalid estimatedCostUpperBoundPerServing: $bound',
      );
    }
    if (budget != null && bound == null) {
      throw const FormatException(
        'Missing estimatedCostUpperBoundPerServing for a budgeted request',
      );
    }
    for (final key in meal.unmetNutritionPreferences) {
      if (!selected.contains(key)) {
        throw FormatException('Unknown or unselected unmet preference "$key"');
      }
    }
  }

  final anyFallback = meals.any((m) => m._isFallback);
  if (!active && anyFallback) {
    throw const FormatException(
      'Fallback priorityMode without nutrition priorities',
    );
  }

  if (active) {
    for (final meal in meals) {
      if (meal.priorityMode == null) {
        throw const FormatException('Missing priorityMode');
      }
    }
  }

  if (anyFallback) {
    if (budget == null) {
      throw const FormatException('Fallback priorityMode without a budget');
    }
    final split = fallbackSplit(meals.length);
    final nutritionFirst = meals
        .where((m) => m.priorityMode == priorityModeNutritionFirst)
        .length;
    final budgetFirst = meals
        .where((m) => m.priorityMode == priorityModeBudgetFirst)
        .length;
    if (nutritionFirst != split.nutritionFirst ||
        budgetFirst != split.budgetFirst) {
      throw FormatException(
        'Fallback groups $nutritionFirst/$budgetFirst do not match the '
        'required ${split.nutritionFirst}/${split.budgetFirst}',
      );
    }
    if (meals.any((m) => m._isFallback && !m._hasNotice)) {
      throw const FormatException('Fallback meal without a constraintNotice');
    }
  }

  if (budget == null) return;

  for (final meal in meals) {
    final bound = meal.estimatedCostUpperBoundPerServing!;
    final mode = meal.priorityMode;
    if (mode != priorityModeNutritionFirst && bound > budget) {
      throw FormatException('A $mode meal costs up to $bound, over $budget');
    }
    if (mode == priorityModeNutritionFirst &&
        bound > budget &&
        !meal._hasNotice) {
      throw const FormatException(
        'Over-budget meal without a constraintNotice',
      );
    }
    if (mode == priorityModeAllPreferences &&
        meal.unmetNutritionPreferences.isNotEmpty) {
      throw const FormatException('allPreferences meal lists unmet priorities');
    }
  }

  if (!meals.any((m) => m.estimatedCostUpperBoundPerServing! <= budget)) {
    throw const FormatException('No meal fits within the budget');
  }

  if (meals.length == 1) {
    final meal = meals.single;
    if (meal.unmetNutritionPreferences.isNotEmpty &&
        (meal.priorityMode != priorityModeBudgetFirst || !meal._hasNotice)) {
      throw const FormatException(
        'A single meal with unmet priorities must be budgetFirst with a notice',
      );
    }
  }
}

/// Budget-first group first, then nutrition-first; stable within each group.
/// Deliberately ignores `eveningScore`.
List<T> orderByPriorityGroup<T>(List<T> meals, String? Function(T) modeOf) {
  int rank(T meal) => switch (modeOf(meal)) {
    priorityModeBudgetFirst => 0,
    priorityModeNutritionFirst => 1,
    _ => 0,
  };
  final indexed = [for (var i = 0; i < meals.length; i++) (i, meals[i])];
  indexed.sort((a, b) {
    final byRank = rank(a.$2).compareTo(rank(b.$2));
    return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

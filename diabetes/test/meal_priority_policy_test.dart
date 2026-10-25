import 'package:diabetes/meals/services/meal_priority_policy.dart';
import 'package:diabetes/settings/models/meal_nutrition_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

const _protein = MealNutritionPreferences(highProtein: true);
const _proteinFiber = MealNutritionPreferences(
  highProtein: true,
  highFiber: true,
);

MealPriorityData _meal(
  String? mode, {
  List<String> unmet = const [],
  String? notice,
  double? cost,
}) => MealPriorityData(
  priorityMode: mode,
  unmetNutritionPreferences: unmet,
  constraintNotice: notice,
  estimatedCostUpperBoundPerServing: cost,
);

MealPriorityData _all(double cost) =>
    _meal(priorityModeAllPreferences, cost: cost);
MealPriorityData _budgetFirst(double cost, {String? notice = 'Relaxed.'}) =>
    _meal(
      priorityModeBudgetFirst,
      unmet: const ['protein'],
      notice: notice,
      cost: cost,
    );
MealPriorityData _nutritionFirst(double cost, {String? notice = 'Over.'}) =>
    _meal(priorityModeNutritionFirst, notice: notice, cost: cost);

void _ok(
  List<MealPriorityData> meals, {
  int? count,
  MealNutritionPreferences prefs = _protein,
  double? budget = 5,
}) => validateMealResponse(
  meals,
  requestedCount: count ?? meals.length,
  preferences: prefs,
  budgetPerServing: budget,
);

Matcher get _rejects => throwsFormatException;

void main() {
  group('fallbackSplit', () {
    test('matches the approved split for 1 to 5', () {
      const expected = {1: (0, 1), 2: (1, 1), 3: (1, 2), 4: (2, 2), 5: (2, 3)};
      expected.forEach((n, split) {
        final result = fallbackSplit(n);
        expect(result.nutritionFirst, split.$1, reason: 'n=$n');
        expect(result.budgetFirst, split.$2, reason: 'n=$n');
        expect(result.nutritionFirst + result.budgetFirst, n);
      });
    });

    test('rejects counts below 1', () {
      expect(() => fallbackSplit(0), throwsArgumentError);
    });
  });

  group('count', () {
    test('rejects empty and wrong counts, accepts the exact count', () {
      expect(
        () => validateMealResponse(
          const [],
          requestedCount: 1,
          preferences: MealNutritionPreferences.none,
        ),
        _rejects,
      );
      expect(
        () => validateMealResponse(
          [_meal(null), _meal(null)],
          requestedCount: 1,
          preferences: MealNutritionPreferences.none,
        ),
        _rejects,
      );
      expect(
        () => validateMealResponse(
          [_meal(null)],
          requestedCount: 2,
          preferences: MealNutritionPreferences.none,
        ),
        _rejects,
      );
      validateMealResponse(
        [_meal(null), _meal(null)],
        requestedCount: 2,
        preferences: MealNutritionPreferences.none,
      );
    });
  });

  group('no priorities', () {
    test('requires no nutrition metadata, with or without budget', () {
      _ok([_meal(null)], prefs: MealNutritionPreferences.none, budget: null);
      _ok(
        [_meal(null, cost: 5)],
        prefs: MealNutritionPreferences.none,
        budget: 5,
      );
    });

    test('still holds every meal to the budget', () {
      expect(
        () => _ok(
          [_meal(null, cost: 9)],
          prefs: MealNutritionPreferences.none,
          budget: 5,
        ),
        _rejects,
      );
      expect(
        () => _ok(
          [_meal(null, cost: 4), _meal(null, cost: 6)],
          prefs: MealNutritionPreferences.none,
          budget: 5,
        ),
        _rejects,
      );
    });

    test('rejects fallback modes without selected priorities', () {
      for (final meal in [_nutritionFirst(9), _budgetFirst(4)]) {
        expect(
          () => _ok([meal], prefs: MealNutritionPreferences.none),
          _rejects,
        );
      }
    });

    test('still needs an upper bound when a budget is set', () {
      expect(
        () => _ok([_meal(null)], prefs: MealNutritionPreferences.none),
        _rejects,
      );
    });

    test('still rejects a bad mode or key if one is present', () {
      expect(
        () => _ok(
          [_meal('bogus')],
          prefs: MealNutritionPreferences.none,
          budget: null,
        ),
        _rejects,
      );
      expect(
        () => _ok(
          [
            _meal(null, unmet: const ['protein']),
          ],
          prefs: MealNutritionPreferences.none,
          budget: null,
        ),
        _rejects,
      );
    });
  });

  group('priorityMode and fields', () {
    test('rejects an invalid or missing priorityMode', () {
      expect(() => _ok([_meal('bogus', cost: 1)]), _rejects);
      expect(() => _ok([_meal(null, cost: 1)]), _rejects);
      expect(() => _ok([_meal(null)], budget: null), _rejects);
    });

    test('rejects missing, negative, or non-finite upper bounds', () {
      expect(() => _ok([_meal(priorityModeAllPreferences)]), _rejects);
      expect(() => _ok([_all(-0.01)]), _rejects);
      expect(() => _ok([_all(double.nan)]), _rejects);
      expect(() => _ok([_all(double.infinity)]), _rejects);
      _ok([_all(0)]);
    });

    test('rejects unknown and unselected unmet keys', () {
      expect(
        () => _ok([
          _meal(
            priorityModeBudgetFirst,
            unmet: const ['sugar'],
            notice: 'n',
            cost: 4,
          ),
        ]),
        _rejects,
      );
      expect(
        () => _ok([
          _meal(
            priorityModeBudgetFirst,
            unmet: const ['fiber'],
            notice: 'n',
            cost: 4,
          ),
        ]),
        _rejects,
        reason: 'fiber was not selected',
      );
    });
  });

  group('budget set, priorities active', () {
    test('accepts an all-preferences response, equal-to-budget included', () {
      _ok([_all(4.99), _all(5)], budget: 5);
      _ok([_all(7.25)], budget: 7.25);
      _ok([_all(0.1 + 0.2)], budget: 0.1 + 0.2);
    });

    test('rejects an all-preferences meal over budget', () {
      expect(() => _ok([_all(5.01)]), _rejects);
      expect(() => _ok([_all(4), _all(5.5)]), _rejects);
    });

    test('rejects allPreferences that lists unmet priorities', () {
      expect(
        () => _ok([
          _meal(priorityModeAllPreferences, unmet: const ['protein'], cost: 3),
        ]),
        _rejects,
      );
    });

    test('accepts exact splits for 2, 3, 4 and 5 meals', () {
      for (var n = 2; n <= 5; n++) {
        final split = fallbackSplit(n);
        _ok([
          for (var i = 0; i < split.budgetFirst; i++) _budgetFirst(4),
          for (var i = 0; i < split.nutritionFirst; i++) _nutritionFirst(8),
        ], prefs: _protein);
      }
    });

    test('rejects a mixed response whose counts differ from the split', () {
      expect(
        () => _ok([_budgetFirst(4), _nutritionFirst(8), _nutritionFirst(8)]),
        _rejects,
        reason: '3 meals need 1 nutrition-first and 2 budget-first, got 2/1',
      );
      expect(
        () => _ok([_budgetFirst(4), _budgetFirst(4), _budgetFirst(4)]),
        _rejects,
      );
      expect(
        () => _ok([_budgetFirst(4), _nutritionFirst(8), _all(3), _all(2)]),
        _rejects,
        reason: 'allPreferences cannot be mixed with fallback groups',
      );
    });

    test('rejects a one-meal nutrition-first fallback', () {
      expect(() => _ok([_nutritionFirst(8)]), _rejects);
    });

    test('rejects fallback meals without a notice', () {
      for (final notice in [null, '', '   ']) {
        expect(
          () => _ok([_budgetFirst(4, notice: notice), _nutritionFirst(8)]),
          _rejects,
          reason: 'budget-first notice "$notice"',
        );
        expect(
          () => _ok([_budgetFirst(4), _nutritionFirst(8, notice: notice)]),
          _rejects,
          reason: 'nutrition-first notice "$notice"',
        );
      }
    });

    test('rejects a budget-first meal over budget', () {
      expect(
        () => _ok([_budgetFirst(5.5), _nutritionFirst(8), _budgetFirst(4)]),
        _rejects,
      );
    });

    test('a nutrition-first meal may be at or under budget', () {
      _ok([_budgetFirst(4), _nutritionFirst(5)]);
    });

    test('rejects when no meal fits the budget', () {
      expect(
        () => _ok([_nutritionFirst(8), _nutritionFirst(9)]),
        _rejects,
        reason: 'also a wrong split, but never acceptable',
      );
      expect(
        () => _ok([
          _meal(priorityModeNutritionFirst, notice: 'n', cost: 9),
          _meal(priorityModeNutritionFirst, notice: 'n', cost: 9),
          _meal(priorityModeNutritionFirst, notice: 'n', cost: 9),
        ]),
        _rejects,
      );
    });

    test('a single unmet priority must be budget-first with a notice', () {
      _ok([_budgetFirst(4)]);
      expect(() => _ok([_budgetFirst(4, notice: null)]), _rejects);
      expect(() => _ok([_budgetFirst(5.5)]), _rejects, reason: 'over budget');
      expect(
        () => _ok([
          _meal(
            priorityModeAllPreferences,
            unmet: const ['protein'],
            notice: 'n',
            cost: 4,
          ),
        ]),
        _rejects,
      );
    });
  });

  group('budget unset, priorities active', () {
    test('accepts allPreferences with or without unmet explanations', () {
      _ok([_meal(priorityModeAllPreferences)], budget: null);
      _ok([
        _meal(
          priorityModeAllPreferences,
          unmet: const ['protein'],
          notice: 'Protein was hard to fit.',
        ),
      ], budget: null);
    });

    test('has no fallback split, so fallback modes are rejected', () {
      expect(
        () => _ok([_budgetFirst(4), _nutritionFirst(8)], budget: null),
        _rejects,
      );
    });

    test('still requires a priorityMode', () {
      expect(() => _ok([_meal(null)], budget: null), _rejects);
    });
  });

  group('all 8 selections', () {
    for (final protein in [false, true]) {
      for (final carbs in [false, true]) {
        for (final fiber in [false, true]) {
          final prefs = MealNutritionPreferences(
            highProtein: protein,
            highCarbs: carbs,
            highFiber: fiber,
          );
          test('protein=$protein carbs=$carbs fiber=$fiber', () {
            if (!prefs.hasAny) {
              _ok([_meal(null)], prefs: prefs, budget: null);
              return;
            }
            _ok([_all(3)], prefs: prefs);
            _ok([
              _meal(
                priorityModeBudgetFirst,
                unmet: [prefs.selectedKeys.first],
                notice: 'n',
                cost: 4,
              ),
            ], prefs: prefs);
            for (final key in const ['protein', 'carbs', 'fiber']) {
              final selected = prefs.selectedKeys.contains(key);
              final meal = _meal(
                priorityModeBudgetFirst,
                unmet: [key],
                notice: 'n',
                cost: 4,
              );
              if (selected) {
                _ok([meal], prefs: prefs);
              } else {
                expect(() => _ok([meal], prefs: prefs), _rejects);
              }
            }
          });
        }
      }
    }
  });

  group('orderByPriorityGroup', () {
    test('puts budget-first first, then nutrition-first, stable in groups', () {
      final items = [
        ('n1', priorityModeNutritionFirst),
        ('b1', priorityModeBudgetFirst),
        ('n2', priorityModeNutritionFirst),
        ('b2', priorityModeBudgetFirst),
      ];
      final ordered = orderByPriorityGroup(items, (item) => item.$2);
      expect(ordered.map((item) => item.$1), ['b1', 'b2', 'n1', 'n2']);
    });

    test('leaves all-preferences answers in the model order', () {
      final items = ['c', 'a', 'b'];
      expect(orderByPriorityGroup(items, (_) => priorityModeAllPreferences), [
        'c',
        'a',
        'b',
      ]);
    });
  });

  test('two selected priorities are validated against both keys', () {
    _ok([
      _meal(
        priorityModeBudgetFirst,
        unmet: const ['protein', 'fiber'],
        notice: 'n',
        cost: 3,
      ),
    ], prefs: _proteinFiber);
  });
}

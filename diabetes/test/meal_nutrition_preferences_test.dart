import 'package:diabetes/settings/data/app_preferences_repository.dart';
import 'package:diabetes/settings/models/meal_nutrition_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_preferences_store.dart';

void main() {
  group('MealNutritionPreferences', () {
    test('defaults to none', () {
      const prefs = MealNutritionPreferences();
      expect(prefs, MealNutritionPreferences.none);
      expect(prefs.hasAny, isFalse);
      expect(prefs.selectedKeys, isEmpty);
      expect(prefs.selectedLabels, isEmpty);
    });

    test('all 8 combinations round-trip through toMap/fromMap', () {
      for (var i = 0; i < 8; i++) {
        final prefs = MealNutritionPreferences(
          highProtein: i & 1 != 0,
          highCarbs: i & 2 != 0,
          highFiber: i & 4 != 0,
        );
        expect(MealNutritionPreferences.fromMap(prefs.toMap()), prefs);
        expect(prefs.hasAny, i != 0);
      }
    });

    test('toMap uses the stored keys', () {
      expect(const MealNutritionPreferences(highProtein: true).toMap(), {
        'highProtein': true,
        'highCarbs': false,
        'highFiber': false,
      });
    });

    test('fromMap tolerates null, non-maps and legacy data', () {
      expect(
        MealNutritionPreferences.fromMap(null),
        MealNutritionPreferences.none,
      );
      expect(
        MealNutritionPreferences.fromMap('x'),
        MealNutritionPreferences.none,
      );
      expect(
        MealNutritionPreferences.fromMap(3),
        MealNutritionPreferences.none,
      );
      expect(
        MealNutritionPreferences.fromMap(<String, Object?>{}),
        MealNutritionPreferences.none,
      );
    });

    test(
      'fromMap treats non-bool values as false and ignores unknown keys',
      () {
        final prefs = MealNutritionPreferences.fromMap({
          'highProtein': 'true',
          'highCarbs': 1,
          'highFiber': true,
          'other': true,
        });
        expect(prefs, const MealNutritionPreferences(highFiber: true));
        expect(
          MealNutritionPreferences.fromMap({'highProtein': null}),
          MealNutritionPreferences.none,
        );
      },
    );

    test('keys and labels are stable and ordered', () {
      const all = MealNutritionPreferences(
        highProtein: true,
        highCarbs: true,
        highFiber: true,
      );
      expect(all.selectedKeys, ['protein', 'carbs', 'fiber']);
      expect(all.selectedLabels, ['High protein', 'High carbs', 'High fiber']);
      const some = MealNutritionPreferences(highProtein: true, highFiber: true);
      expect(some.selectedKeys, ['protein', 'fiber']);
      expect(some.selectedLabels, ['High protein', 'High fiber']);
      expect(MealNutritionPreferences.proteinKey, 'protein');
      expect(MealNutritionPreferences.carbsKey, 'carbs');
      expect(MealNutritionPreferences.fiberKey, 'fiber');
    });

    test('copyWith and equality', () {
      const base = MealNutritionPreferences(highCarbs: true);
      expect(base.copyWith(), base);
      expect(base.copyWith(highProtein: true).highProtein, isTrue);
      expect(base.copyWith(highCarbs: false), MealNutritionPreferences.none);
      expect(base, const MealNutritionPreferences(highCarbs: true));
      expect(
        base.hashCode,
        const MealNutritionPreferences(highCarbs: true).hashCode,
      );
      expect(base, isNot(MealNutritionPreferences.none));
    });
  });

  group('repository seams', () {
    test('write payload nests the map and stamps updatedAt', () {
      final payload = mealNutritionPreferencesWritePayload(
        const MealNutritionPreferences(highProtein: true),
      );
      expect(
        payload.keys,
        containsAll(['mealNutritionPreferences', 'updatedAt']),
      );
      expect(payload['mealNutritionPreferences'], {
        'highProtein': true,
        'highCarbs': false,
        'highFiber': false,
      });
      expect(payload.length, 2);
    });

    test('user data parsing handles missing and malformed data', () {
      expect(
        mealNutritionPreferencesFromUserData(null),
        MealNutritionPreferences.none,
      );
      expect(
        mealNutritionPreferencesFromUserData({'other': 1}),
        MealNutritionPreferences.none,
      );
      expect(
        mealNutritionPreferencesFromUserData({
          'mealNutritionPreferences': 'bad',
        }),
        MealNutritionPreferences.none,
      );
      expect(
        mealNutritionPreferencesFromUserData({
          'mealNutritionPreferences': {'highCarbs': true},
        }),
        const MealNutritionPreferences(highCarbs: true),
      );
    });
  });

  group('FakePreferencesStore', () {
    test('replays, saves and can fail', () async {
      final store = FakePreferencesStore();
      final seen = <MealNutritionPreferences>[];
      final sub = store.watchMealNutritionPreferences('u').listen(seen.add);
      await store.saveMealNutritionPreferences(
        'u',
        const MealNutritionPreferences(highFiber: true),
      );
      await pumpEventQueue();
      expect(seen, [
        MealNutritionPreferences.none,
        const MealNutritionPreferences(highFiber: true),
      ]);
      expect(store.saveMealNutritionPreferencesCalls, 1);
      store.saveMealNutritionPreferencesError = StateError('offline');
      expect(
        store.saveMealNutritionPreferences('u', MealNutritionPreferences.none),
        throwsStateError,
      );
      await sub.cancel();
    });
  });
}

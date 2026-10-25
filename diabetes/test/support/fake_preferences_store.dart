import 'dart:async';

import 'package:diabetes/settings/data/app_preferences_repository.dart';
import 'package:diabetes/settings/models/meal_nutrition_preferences.dart';

/// In-memory [AppPreferencesStore] for widget tests: no Firestore, and every
/// watch stream replays the current value so a listener always gets one.
class FakePreferencesStore implements AppPreferencesStore {
  FakePreferencesStore({
    bool mealBalanceEnabled = false,
    bool mealQaTipSeen = false,
    bool firstMealGuidePending = false,
    MealNutritionPreferences nutritionPreferences =
        MealNutritionPreferences.none,
  }) {
    _nutritionValue = nutritionPreferences;
    _mealBalanceValue = mealBalanceEnabled;
    _qaTipValue = mealQaTipSeen;
    _firstMealGuideValue = firstMealGuidePending;
  }

  final List<StreamController<bool>> _mealBalanceListeners = [];
  final List<StreamController<bool>> _qaTipListeners = [];
  final List<StreamController<bool>> _firstMealGuideListeners = [];

  final List<StreamController<MealNutritionPreferences>> _nutritionListeners =
      [];
  late MealNutritionPreferences _nutritionValue;

  /// Every value passed to saveMealNutritionPreferences (including failures).
  final List<MealNutritionPreferences> savedNutritionPreferences = [];
  int saveMealNutritionPreferencesCalls = 0;

  /// Set to fail the nutrition save, mirroring an offline device.
  Object? saveMealNutritionPreferencesError;

  /// When set, saves wait on it, so a test can hold a write in flight.
  Completer<void>? saveMealNutritionPreferencesGate;

  /// Highest number of nutrition saves running at once.
  int maxConcurrentNutritionSaves = 0;
  int _nutritionSavesInFlight = 0;

  /// When set, the nutrition watch emits this error instead of a value.
  Object? watchMealNutritionPreferencesError;

  /// When false the nutrition watch stays silent until a value is pushed.
  bool watchMealNutritionPreferencesEmitsInitial = true;
  int watchMealNutritionPreferencesCalls = 0;
  int activeNutritionListeners = 0;

  /// Pushes a value as if it arrived from another device.
  void setMealNutritionPreferences(MealNutritionPreferences value) {
    _nutritionValue = value;
    for (final controller in List.of(_nutritionListeners)) {
      controller.add(value);
    }
  }

  late bool _mealBalanceValue;
  late bool _qaTipValue;
  late bool _firstMealGuideValue;

  /// How many times the guide was marked done, so tests can assert "once".
  int completeFirstMealGuideCalls = 0;
  int saveMealQaTipSeenCalls = 0;

  /// Set to fail the guide write, mirroring an offline device.
  Object? completeFirstMealGuideError;

  void setFirstMealGuidePending(bool pending) {
    _firstMealGuideValue = pending;
    _emit(_firstMealGuideListeners, pending);
  }

  @override
  Stream<bool> watchMealBalanceAgentEnabled(String userId) =>
      _watch(_mealBalanceListeners, () => _mealBalanceValue);

  @override
  Future<void> saveMealBalanceAgentEnabled(String userId, bool enabled) async {
    _mealBalanceValue = enabled;
    _emit(_mealBalanceListeners, enabled);
  }

  @override
  Stream<bool> watchMealQaTipSeen(String userId) =>
      _watch(_qaTipListeners, () => _qaTipValue);

  @override
  Future<void> saveMealQaTipSeen(String userId) async {
    saveMealQaTipSeenCalls++;
    _qaTipValue = true;
    _emit(_qaTipListeners, true);
  }

  @override
  Stream<bool> watchFirstMealGuidePending(String userId) =>
      _watch(_firstMealGuideListeners, () => _firstMealGuideValue);

  @override
  Future<void> completeFirstMealGuide(String userId) async {
    completeFirstMealGuideCalls++;
    final error = completeFirstMealGuideError;
    if (error != null) throw error;
    setFirstMealGuidePending(false);
  }

  @override
  Stream<MealNutritionPreferences> watchMealNutritionPreferences(
    String userId,
  ) {
    late StreamController<MealNutritionPreferences> controller;
    controller = StreamController<MealNutritionPreferences>(
      onListen: () {
        watchMealNutritionPreferencesCalls++;
        activeNutritionListeners++;
        _nutritionListeners.add(controller);
        final error = watchMealNutritionPreferencesError;
        if (error != null) {
          controller.addError(error);
        } else if (watchMealNutritionPreferencesEmitsInitial) {
          controller.add(_nutritionValue);
        }
      },
      onCancel: () {
        activeNutritionListeners--;
        _nutritionListeners.remove(controller);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> saveMealNutritionPreferences(
    String userId,
    MealNutritionPreferences preferences,
  ) async {
    saveMealNutritionPreferencesCalls++;
    savedNutritionPreferences.add(preferences);
    _nutritionSavesInFlight++;
    if (_nutritionSavesInFlight > maxConcurrentNutritionSaves) {
      maxConcurrentNutritionSaves = _nutritionSavesInFlight;
    }
    try {
      await saveMealNutritionPreferencesGate?.future;
      final error = saveMealNutritionPreferencesError;
      if (error != null) throw error;
      setMealNutritionPreferences(preferences);
    } finally {
      _nutritionSavesInFlight--;
    }
  }

  /// onListen fires synchronously, so a write made right after `listen` still
  /// reaches the subscriber.
  Stream<bool> _watch(
    List<StreamController<bool>> listeners,
    bool Function() current,
  ) {
    late StreamController<bool> controller;
    controller = StreamController<bool>(
      onListen: () {
        listeners.add(controller);
        controller.add(current());
      },
      onCancel: () => listeners.remove(controller),
    );
    return controller.stream;
  }

  void _emit(List<StreamController<bool>> listeners, bool value) {
    for (final controller in List.of(listeners)) {
      controller.add(value);
    }
  }
}

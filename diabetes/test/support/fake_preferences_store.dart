import 'dart:async';

import 'package:diabetes/settings/data/app_preferences_repository.dart';

/// In-memory [AppPreferencesStore] for widget tests: no Firestore, and every
/// watch stream replays the current value so a listener always gets one.
class FakePreferencesStore implements AppPreferencesStore {
  FakePreferencesStore({
    bool mealBalanceEnabled = false,
    bool mealQaTipSeen = false,
    bool firstMealGuidePending = false,
  }) {
    _mealBalanceValue = mealBalanceEnabled;
    _qaTipValue = mealQaTipSeen;
    _firstMealGuideValue = firstMealGuidePending;
  }

  final List<StreamController<bool>> _mealBalanceListeners = [];
  final List<StreamController<bool>> _qaTipListeners = [];
  final List<StreamController<bool>> _firstMealGuideListeners = [];

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

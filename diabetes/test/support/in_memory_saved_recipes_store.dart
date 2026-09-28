import 'dart:async';

import 'package:diabetes/main.dart' show MealRecommendation;
import 'package:diabetes/meals/saved/saved_recipe.dart';
import 'package:diabetes/meals/saved/saved_recipes_repository.dart';

/// In-memory [SavedRecipesStore] for tests: same fingerprint rules as
/// Firestore, no network.
class InMemorySavedRecipesStore implements SavedRecipesStore {
  InMemorySavedRecipesStore({List<SavedRecipe> initial = const []}) {
    for (final recipe in initial) {
      _recipes[recipe.id] = recipe;
    }
  }

  final Map<String, SavedRecipe> _recipes = {};
  final List<StreamController<List<SavedRecipe>>> _listeners = [];

  int saveCalls = 0;
  int removeCalls = 0;

  /// Set to make the next write fail, mirroring an offline device.
  Object? writeError;

  List<SavedRecipe> get recipes => _sorted();

  @override
  Stream<List<SavedRecipe>> watchAll(String userId) {
    // onListen fires synchronously, so a write right after `listen` is never
    // missed the way a lazily-attached broadcast stream would miss it.
    late StreamController<List<SavedRecipe>> controller;
    controller = StreamController<List<SavedRecipe>>(
      onListen: () {
        _listeners.add(controller);
        controller.add(_sorted());
      },
      onCancel: () => _listeners.remove(controller),
    );
    return controller.stream;
  }

  @override
  Future<void> save(String userId, MealRecommendation recipe) async {
    saveCalls++;
    final error = writeError;
    if (error != null) throw error;
    final id = recipeFingerprint(recipe);
    _recipes[id] = SavedRecipe(
      id: id,
      recipe: recipe,
      savedAt: DateTime(2026, 9, 28, 12, saveCalls),
    );
    _notify();
  }

  @override
  Future<void> remove(String userId, String recipeId) async {
    removeCalls++;
    final error = writeError;
    if (error != null) throw error;
    _recipes.remove(recipeId);
    _notify();
  }

  void _notify() {
    for (final controller in List.of(_listeners)) {
      controller.add(_sorted());
    }
  }

  List<SavedRecipe> _sorted() {
    final all = _recipes.values.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return all;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../main.dart' show MealRecommendation;
import 'saved_recipe.dart';

/// Reads and writes the user's saved recipes. Injected so screens and tests
/// can swap in an in-memory store.
abstract interface class SavedRecipesStore {
  /// Newest first.
  Stream<List<SavedRecipe>> watchAll(String userId);

  /// Idempotent: saving the same recipe again overwrites its one document.
  Future<void> save(String userId, MealRecommendation recipe);

  Future<void> remove(String userId, String recipeId);
}

class SavedRecipesRepository implements SavedRecipesStore {
  SavedRecipesRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String userId) =>
      _firestore.collection('users').doc(userId).collection('savedRecipes');

  @override
  Stream<List<SavedRecipe>> watchAll(String userId) => _collection(userId)
      .orderBy('savedAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            SavedRecipe.fromMap(doc.id, doc.data()),
        ],
      );

  @override
  Future<void> save(String userId, MealRecommendation recipe) {
    final id = recipeFingerprint(recipe);
    return _collection(userId)
        .doc(id)
        .set(
          SavedRecipe(
            id: id,
            recipe: recipe,
            savedAt: DateTime.now(),
          ).toFirestore(),
        );
  }

  @override
  Future<void> remove(String userId, String recipeId) =>
      _collection(userId).doc(recipeId).delete();
}

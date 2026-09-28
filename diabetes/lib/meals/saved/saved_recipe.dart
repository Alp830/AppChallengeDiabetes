import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../main.dart' show MealRecommendation;

/// A recipe the user chose to keep, stored whole so reopening it never needs
/// another AI request.
class SavedRecipe {
  const SavedRecipe({
    required this.id,
    required this.recipe,
    required this.savedAt,
  });

  /// Doc id — the [recipeFingerprint] of [recipe], so saving the same dish
  /// twice updates one document instead of piling up duplicates.
  final String id;
  final MealRecommendation recipe;
  final DateTime savedAt;

  Map<String, dynamic> toFirestore() => {
    'recipe': recipe.toJson(),
    'savedAt': Timestamp.fromDate(savedAt),
  };

  factory SavedRecipe.fromMap(String id, Map<String, dynamic> data) {
    final savedAt = data['savedAt'];
    return SavedRecipe(
      id: id,
      recipe: MealRecommendation.fromJson(
        Map<String, dynamic>.from(data['recipe'] as Map),
      ),
      savedAt: switch (savedAt) {
        Timestamp() => savedAt.toDate(),
        DateTime() => savedAt,
        String() => DateTime.tryParse(savedAt) ?? DateTime.now(),
        _ => DateTime.now(),
      },
    );
  }
}

/// Stable id for a recipe: the dish name plus its ingredients, normalized so
/// case, spacing, and ingredient order don't create a second copy.
String recipeFingerprint(MealRecommendation recipe) {
  final ingredients = recipe.ingredients.map(_normalize).toList()..sort();
  final payload = [_normalize(recipe.dishName), ...ingredients].join('\n');
  return _fnv1a64Hex(payload);
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// FNV-1a, 64-bit, as 16 hex characters. Chosen over a crypto hash to avoid a
/// new dependency: this only needs to be stable and collision-shy.
String _fnv1a64Hex(String input) {
  // Offset basis and prime for the 64-bit variant.
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in utf8.encode(input)) {
    hash = (hash ^ BigInt.from(byte)) & mask;
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

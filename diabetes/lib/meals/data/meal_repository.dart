import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/meal_models.dart';

class MealRepository {
  MealRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  DocumentReference<Map<String, dynamic>> _user(String userId) =>
      _firestore.collection('users').doc(userId);

  Stream<List<MealEvent>> watchMeals(String userId, {int limit = 100}) =>
      _user(userId)
          .collection('mealEvents')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => MealEvent.fromFirestore(doc.id, doc.data()))
                .toList(),
          );

  Stream<List<MealGroup>> watchGroups(String userId) => _user(userId)
      .collection('mealGroups')
      .orderBy('name')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => MealGroup.fromFirestore(doc.id, doc.data()))
            .toList(),
      );

  Stream<List<MealTemplate>> watchTemplates(String userId) => _user(userId)
      .collection('mealTemplates')
      .orderBy('updatedAt', descending: true)
      .limit(20)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => MealTemplate.fromFirestore(doc.id, doc.data()))
            .toList(),
      );

  Future<void> saveTemplate(String userId, MealEvent meal) => _user(userId)
      .collection('mealTemplates')
      .add({
        'name': meal.name,
        'mealType': meal.mealType,
        'portion': meal.portion.name,
        'carbBand': meal.carbBand.name,
        'mealOrder': meal.mealOrder.name,
        'preparation': meal.preparation.name,
        'restaurant': meal.restaurant,
        'components': meal.components,
        'hasProtein': meal.hasProtein,
        'hasFat': meal.hasFat,
        'hasFiber': meal.hasFiber,
        'favorite': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> renameGroup(String userId, String groupId, String name) =>
      _user(userId).collection('mealGroups').doc(groupId).update({
        'name': name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> mergeGroups(
    String userId,
    String sourceGroupId,
    String destinationGroupId,
  ) async {
    final meals = await _user(userId)
        .collection('mealEvents')
        .where('groupId', isEqualTo: sourceGroupId)
        .get();
    final batch = _firestore.batch();
    for (final meal in meals.docs) {
      batch.update(meal.reference, {
        'groupId': destinationGroupId,
        'groupConfirmed': true,
      });
    }
    batch.delete(_user(userId).collection('mealGroups').doc(sourceGroupId));
    await batch.commit();
  }

  Future<String> saveMeal(String userId, MealEvent meal, {Uint8List? photo}) async {
    final reference = _user(userId).collection('mealEvents').doc();
    String? photoUrl;
    if (photo != null) {
      final storageReference = _storage.ref('users/$userId/mealPhotos/${reference.id}.jpg');
      await storageReference.putData(
        photo,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      photoUrl = await storageReference.getDownloadURL();
    }
    await reference.set(
      MealEvent(
        id: reference.id,
        name: meal.name,
        timestamp: meal.timestamp,
        mealType: meal.mealType,
        portion: meal.portion,
        carbBand: meal.carbBand,
        mealOrder: meal.mealOrder,
        preparation: meal.preparation,
        restaurant: meal.restaurant,
        carbohydrateGrams: meal.carbohydrateGrams,
        hasProtein: meal.hasProtein,
        hasFat: meal.hasFat,
        hasFiber: meal.hasFiber,
        components: meal.components,
        nearbyMovement: meal.nearbyMovement,
        notes: meal.notes,
        photoUrl: photoUrl,
      ).toFirestore(),
    );
    return reference.id;
  }

  Future<String> createGroup(String userId, String name, String summary) async {
    final reference = await _user(userId).collection('mealGroups').add({
      'name': name,
      'summary': summary,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return reference.id;
  }

  Future<void> assignGroup(
    String userId,
    String mealId,
    String groupId,
    double confidence, {
    bool confirmed = false,
  }) async {
    final mealReference = _user(userId).collection('mealEvents').doc(mealId);
    final meal = await mealReference.get();
    await mealReference.update({
      'groupId': groupId,
      'groupConfidence': confidence,
      'groupConfirmed': confirmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (confirmed && meal.exists) {
      final data = meal.data()!;
      final example = '${data['name'] ?? 'Meal'}: '
          '${(data['components'] as List? ?? const []).whereType<String>().join(', ')}';
      await _user(userId).collection('mealGroups').doc(groupId).set({
        'correctionExamples': FieldValue.arrayUnion([example]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> unassignGroup(String userId, String mealId) =>
      _user(userId).collection('mealEvents').doc(mealId).update({
        'groupId': FieldValue.delete(),
        'groupConfidence': FieldValue.delete(),
        'groupConfirmed': false,
      });

  Future<void> deleteMeal(String userId, MealEvent meal) async {
    await _user(userId).collection('mealEvents').doc(meal.id).delete();
    if (meal.photoUrl != null) {
      try {
        await _storage.refFromURL(meal.photoUrl!).delete();
      } catch (_) {}
    }
  }
}

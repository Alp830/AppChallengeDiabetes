import 'package:cloud_firestore/cloud_firestore.dart';

abstract interface class AppPreferencesStore {
  Stream<bool> watchMealBalanceAgentEnabled(String userId);
  Future<void> saveMealBalanceAgentEnabled(String userId, bool enabled);
}

class AppPreferencesRepository implements AppPreferencesStore {
  AppPreferencesRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _user(String userId) =>
      _firestore.collection('users').doc(userId);

  @override
  Stream<bool> watchMealBalanceAgentEnabled(String userId) =>
      _user(userId).snapshots().map(
        (snapshot) =>
            snapshot.data()?['mealBalanceAgentEnabled'] as bool? ?? false,
      );

  @override
  Future<void> saveMealBalanceAgentEnabled(String userId, bool enabled) =>
      _user(userId).set({
        'mealBalanceAgentEnabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

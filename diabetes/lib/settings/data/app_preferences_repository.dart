import 'package:cloud_firestore/cloud_firestore.dart';

abstract interface class AppPreferencesStore {
  Stream<bool> watchMealBalanceAgentEnabled(String userId);
  Future<void> saveMealBalanceAgentEnabled(String userId, bool enabled);

  /// Whether the one-time "tap any ingredient or step to ask about it" tip
  /// inside the meal Q&A sheet has already been shown.
  Stream<bool> watchMealQaTipSeen(String userId);
  Future<void> saveMealQaTipSeen(String userId);

  /// Whether this account still has the first-meal guide waiting for it.
  /// Only accounts created after the guide shipped carry the `'pending'`
  /// value, so existing users never see the Home card.
  Stream<bool> watchFirstMealGuidePending(String userId);

  /// Marks the guide finished: the user got their first recommendation or
  /// skipped the tour.
  Future<void> completeFirstMealGuide(String userId);
}

/// Value stored in `users/{uid}.firstMealGuide` while the guide is waiting.
const firstMealGuidePendingValue = 'pending';

/// Value stored once the guide has been finished or skipped.
const firstMealGuideDoneValue = 'done';

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

  @override
  Stream<bool> watchMealQaTipSeen(String userId) => _user(userId)
      .snapshots()
      .map((snapshot) => snapshot.data()?['mealQaTipSeen'] as bool? ?? false);

  @override
  Future<void> saveMealQaTipSeen(String userId) => _user(userId).set({
    'mealQaTipSeen': true,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  @override
  Stream<bool> watchFirstMealGuidePending(String userId) =>
      _user(userId).snapshots().map(
        (snapshot) =>
            snapshot.data()?['firstMealGuide'] == firstMealGuidePendingValue,
      );

  @override
  Future<void> completeFirstMealGuide(String userId) => _user(userId).set({
    'firstMealGuide': firstMealGuideDoneValue,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

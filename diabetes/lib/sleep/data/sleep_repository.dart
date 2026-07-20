import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/sleep_models.dart';

class SleepRepository {
  SleepRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _sleepLogs(String userId) {
    return _firestore.collection('users').doc(userId).collection('sleepLogs');
  }

  DocumentReference<Map<String, dynamic>> _settingsDoc(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('sleepSettings')
        .doc('profile');
  }

  Stream<List<SleepLog>> watchRecentSleep(String userId, {int limit = 30}) {
    return _sleepLogs(userId)
        .orderBy('bedtime', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((document) => SleepLog.fromFirestore(document.id, document.data()))
              .toList(),
        );
  }

  Stream<SleepLog?> watchLatest(String userId) {
    return _sleepLogs(userId)
        .orderBy('bedtime', descending: true)
        .limit(1)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.isEmpty
              ? null
              : SleepLog.fromFirestore(
                  snapshot.docs.first.id,
                  snapshot.docs.first.data(),
                ),
        );
  }

  Future<String> saveSleepLog(String userId, SleepLog log) async {
    final document = await _sleepLogs(userId).add(log.toFirestore());
    return document.id;
  }

  Future<void> updateSleepLog(String userId, String id, SleepLog log) {
    return _sleepLogs(userId).doc(id).update(log.toFirestore());
  }

  Future<void> deleteSleepLog(String userId, String id) {
    return _sleepLogs(userId).doc(id).delete();
  }

  Stream<SleepSettings> watchSettings(String userId) {
    return _settingsDoc(
      userId,
    ).snapshots().map((snapshot) => SleepSettings.fromFirestore(snapshot.data()));
  }

  Future<SleepSettings> getSettings(String userId) async {
    final snapshot = await _settingsDoc(userId).get();
    return SleepSettings.fromFirestore(snapshot.data());
  }

  Future<void> saveSettings(String userId, SleepSettings settings) {
    return _settingsDoc(
      userId,
    ).set(settings.toFirestore(), SetOptions(merge: true));
  }

  /// Live-capture: records that the user just went to bed. Stored on the
  /// settings singleton so it survives an app restart until they wake.
  Future<void> startPendingBedtime(String userId, DateTime bedtime) {
    return _settingsDoc(userId).set({
      'pendingBedtime': Timestamp.fromDate(bedtime),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearPendingBedtime(String userId) {
    return _settingsDoc(userId).set({
      'pendingBedtime': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

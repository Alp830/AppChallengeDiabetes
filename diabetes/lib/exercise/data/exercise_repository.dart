import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/exercise_profile.dart';
import '../models/workout_session.dart';

class ExerciseRepository {
  ExerciseRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _sessions(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('workoutSessions');
  }

  Stream<List<WorkoutSession>> watchRecentSessions(
    String userId, {
    int limit = 50,
  }) {
    return _sessions(userId)
        .orderBy('startedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (document) =>
                    WorkoutSession.fromFirestore(document.id, document.data()),
              )
              .toList(),
        );
  }

  Stream<List<WorkoutSession>> watchSessionsForDay(
    String userId,
    DateTime localDay,
  ) {
    final start = DateTime(localDay.year, localDay.month, localDay.day);
    final end = start.add(const Duration(days: 1));

    return _sessions(userId)
        .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startedAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('startedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (document) =>
                    WorkoutSession.fromFirestore(document.id, document.data()),
              )
              .toList(),
        );
  }

  Future<String> saveCompletedSession(
    String userId,
    WorkoutSession session,
  ) async {
    final document = await _sessions(userId).add(session.toFirestore());
    return document.id;
  }

  Future<void> deleteSession(String userId, String sessionId) {
    return _sessions(userId).doc(sessionId).delete();
  }

  Stream<ExerciseProfile> watchProfile(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('exerciseProfile')
        .doc('settings')
        .snapshots()
        .map((snapshot) => ExerciseProfile.fromFirestore(snapshot.data()));
  }

  Future<ExerciseProfile> getProfile(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('exerciseProfile')
        .doc('settings')
        .get();
    return ExerciseProfile.fromFirestore(snapshot.data());
  }

  Future<void> saveProfile(String userId, ExerciseProfile profile) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('exerciseProfile')
        .doc('settings')
        .set({
          ...profile.toFirestore(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
}

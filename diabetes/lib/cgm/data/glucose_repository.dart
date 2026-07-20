import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/glucose_models.dart';

class GlucoseRepository {
  GlucoseRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _user(String userId) =>
      _firestore.collection('users').doc(userId);

  Stream<GlucoseSettings> watchSettings(String userId) => _user(userId)
      .collection('glucoseSettings')
      .doc('profile')
      .snapshots()
      .map((snapshot) => GlucoseSettings.fromFirestore(snapshot.data()));

  Future<void> saveSettings(String userId, GlucoseSettings settings) =>
      _user(userId)
          .collection('glucoseSettings')
          .doc('profile')
          .set(settings.toFirestore(), SetOptions(merge: true));

  Stream<List<GlucoseReading>> watchDay(String userId, DateTime day) {
    final date = _dayId(day);
    return _user(userId)
        .collection('glucoseDays')
        .where('dateId', isEqualTo: date)
        .snapshots()
        .map((snapshot) {
          final bySource = <GlucoseSource, List<GlucoseReading>>{};
          for (final document in snapshot.docs) {
            final source = document.id.startsWith('demo-')
                ? GlucoseSource.demo
                : GlucoseSource.libreView;
            final raw = document.data()['readings'] as List? ?? const [];
            bySource[source] = raw
                .whereType<Map>()
                .map(
                  (item) => GlucoseReading.fromFirestore(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList();
          }
          final readings = bySource[GlucoseSource.libreView] ??
              bySource[GlucoseSource.demo] ??
              const <GlucoseReading>[];
          readings.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          return readings;
        });
  }

  Future<List<GlucoseReading>> getRange(
    String userId,
    DateTime start,
    DateTime end,
  ) async {
    final snapshot = await _user(userId)
        .collection('glucoseDays')
        .where('dateId', isGreaterThanOrEqualTo: _dayId(start))
        .where('dateId', isLessThanOrEqualTo: _dayId(end))
        .get();
    final real = <GlucoseReading>[];
    final demo = <GlucoseReading>[];
    for (final document in snapshot.docs) {
      final target = document.id.startsWith('demo-') ? demo : real;
      final raw = document.data()['readings'] as List? ?? const [];
      target.addAll(
        raw.whereType<Map>().map(
          (item) => GlucoseReading.fromFirestore(
            Map<String, dynamic>.from(item),
          ),
        ),
      );
    }
    final selected = real.isNotEmpty ? real : demo;
    selected.removeWhere(
      (reading) =>
          reading.timestamp.isBefore(start) || !reading.timestamp.isBefore(end),
    );
    selected.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return selected;
  }

  Future<void> saveImport(String userId, CgmImportPreview preview) async {
    final grouped = <String, List<GlucoseReading>>{};
    for (final reading in preview.readings) {
      grouped.putIfAbsent(_dayId(reading.timestamp), () => []).add(reading);
    }
    for (final entry in grouped.entries) {
      final prefix = preview.source == GlucoseSource.demo ? 'demo' : 'libre';
      final reference = _user(userId)
          .collection('glucoseDays')
          .doc('$prefix-${entry.key}');
      final existing = await reference.get();
      final readingsById = <String, GlucoseReading>{};
      final rawExisting = existing.data()?['readings'] as List? ?? const [];
      for (final item in rawExisting.whereType<Map>()) {
        final reading = GlucoseReading.fromFirestore(
          Map<String, dynamic>.from(item),
        );
        readingsById[reading.id] = reading;
      }
      for (final reading in entry.value) {
        readingsById[reading.id] = reading;
      }
      final readings = readingsById.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      await reference.set({
        'dateId': entry.key,
        'source': preview.source.name,
        'readings': readings.map((reading) => reading.toFirestore()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await _user(userId).collection('glucoseImports').add({
      'source': preview.source.name,
      'deviceId': preview.deviceId,
      'readingCount': preview.readings.length,
      'rejectedRows': preview.rejectedRows,
      'duplicateRows': preview.duplicateRows,
      'startedAt': preview.startedAt == null
          ? null
          : Timestamp.fromDate(preview.startedAt!),
      'endedAt': preview.endedAt == null
          ? null
          : Timestamp.fromDate(preview.endedAt!),
      'parserVersion': 1,
      'importedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Whether the user has any imported glucose data at all (LibreView or demo).
  /// [saveImport] always writes a `glucoseImports` doc and [deleteSource]
  /// removes them, so the presence of one doc is an exact, cheap proxy. Glucose
  /// surfaces use this to stay hidden until the user actually has data.
  Stream<bool> watchHasGlucoseData(String userId) => _user(userId)
      .collection('glucoseImports')
      .limit(1)
      .snapshots()
      .map((snapshot) => snapshot.docs.isNotEmpty);

  Stream<QuerySnapshot<Map<String, dynamic>>> watchImports(String userId) =>
      _user(userId)
          .collection('glucoseImports')
          .orderBy('importedAt', descending: true)
          .limit(20)
          .snapshots();

  Future<void> deleteSource(String userId, GlucoseSource source) async {
    final prefix = source == GlucoseSource.demo ? 'demo-' : 'libre-';
    final days = await _user(userId).collection('glucoseDays').get();
    final imports = await _user(userId)
        .collection('glucoseImports')
        .where('source', isEqualTo: source.name)
        .get();
    final references = [
      ...days.docs.where((doc) => doc.id.startsWith(prefix)).map((doc) => doc.reference),
      ...imports.docs.map((doc) => doc.reference),
    ];
    for (var offset = 0; offset < references.length; offset += 450) {
      final batch = _firestore.batch();
      for (final reference in references.skip(offset).take(450)) {
        batch.delete(reference);
      }
      await batch.commit();
    }
  }
}

String _dayId(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

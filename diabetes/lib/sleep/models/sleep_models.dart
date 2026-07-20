import 'package:cloud_firestore/cloud_firestore.dart';

/// Where a [SleepLog] came from. Manual is the only source built today; the
/// wearable value + the nullable stage fields on [SleepLog] exist so an Apple
/// Health / Health Connect importer can drop in later with no schema migration.
enum SleepSource { manual, wearable, unknown }

/// A single night of sleep, anchored to the morning it ends ([dateId]).
class SleepLog {
  const SleepLog({
    required this.id,
    required this.bedtime,
    required this.wakeTime,
    required this.quality,
    required this.wakeUps,
    this.source = SleepSource.manual,
    this.note,
    // Wearable-ready. All null for manual logs.
    this.deepMinutes,
    this.lightMinutes,
    this.remMinutes,
    this.awakeMinutes,
  });

  final String id;
  final DateTime bedtime;
  final DateTime wakeTime;

  /// Subjective quality, 1 (poor) to 5 (great).
  final int quality;

  /// Number of times the user woke during the night.
  final int wakeUps;

  final SleepSource source;
  final String? note;

  final int? deepMinutes;
  final int? lightMinutes;
  final int? remMinutes;
  final int? awakeMinutes;

  /// Total time in bed, in minutes. Clamped at 0 for malformed inputs.
  int get durationMinutes {
    final minutes = wakeTime.difference(bedtime).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  /// Whole hours of the night, for display (e.g. "7h 45m").
  int get durationHours => durationMinutes ~/ 60;

  int get durationRemainderMinutes => durationMinutes % 60;

  /// A night belongs to the calendar day it ends on.
  String get dateId => _dayId(wakeTime);

  bool get hasStageData =>
      deepMinutes != null ||
      lightMinutes != null ||
      remMinutes != null ||
      awakeMinutes != null;

  SleepLog copyWith({
    DateTime? bedtime,
    DateTime? wakeTime,
    int? quality,
    int? wakeUps,
    SleepSource? source,
    String? note,
    int? deepMinutes,
    int? lightMinutes,
    int? remMinutes,
    int? awakeMinutes,
  }) {
    return SleepLog(
      id: id,
      bedtime: bedtime ?? this.bedtime,
      wakeTime: wakeTime ?? this.wakeTime,
      quality: quality ?? this.quality,
      wakeUps: wakeUps ?? this.wakeUps,
      source: source ?? this.source,
      note: note ?? this.note,
      deepMinutes: deepMinutes ?? this.deepMinutes,
      lightMinutes: lightMinutes ?? this.lightMinutes,
      remMinutes: remMinutes ?? this.remMinutes,
      awakeMinutes: awakeMinutes ?? this.awakeMinutes,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'schemaVersion': 1,
    'bedtime': Timestamp.fromDate(bedtime),
    'wakeTime': Timestamp.fromDate(wakeTime),
    'dateId': dateId,
    'quality': quality,
    'wakeUps': wakeUps,
    'source': source.name,
    if (note != null) 'note': note,
    if (deepMinutes != null) 'deepMinutes': deepMinutes,
    if (lightMinutes != null) 'lightMinutes': lightMinutes,
    if (remMinutes != null) 'remMinutes': remMinutes,
    if (awakeMinutes != null) 'awakeMinutes': awakeMinutes,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory SleepLog.fromFirestore(String id, Map<String, dynamic> data) {
    return SleepLog(
      id: id,
      bedtime: (data['bedtime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      wakeTime: (data['wakeTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      quality: (data['quality'] as num?)?.toInt() ?? 3,
      wakeUps: (data['wakeUps'] as num?)?.toInt() ?? 0,
      source: _enumByName(SleepSource.values, data['source'], SleepSource.manual),
      note: (data['note'] as String?)?.trim().isEmpty ?? true
          ? null
          : (data['note'] as String?)?.trim(),
      deepMinutes: (data['deepMinutes'] as num?)?.toInt(),
      lightMinutes: (data['lightMinutes'] as num?)?.toInt(),
      remMinutes: (data['remMinutes'] as num?)?.toInt(),
      awakeMinutes: (data['awakeMinutes'] as num?)?.toInt(),
    );
  }
}

/// What the user wants the sleep layer to emphasize (S9). Overnight lows are a
/// safety concern and surface regardless of this choice; the others govern which
/// gentle nudges appear so the app stays quiet rather than noisy.
enum SleepFocus { balanced, regularity, overnightLows, lateDinnerHighs }

extension SleepFocusDisplay on SleepFocus {
  String get label {
    switch (this) {
      case SleepFocus.balanced:
        return 'Balanced';
      case SleepFocus.regularity:
        return 'Regularity';
      case SleepFocus.overnightLows:
        return 'Overnight lows';
      case SleepFocus.lateDinnerHighs:
        return 'Late-dinner highs';
    }
  }

  String get description {
    switch (this) {
      case SleepFocus.balanced:
        return 'Show every relevant nudge — nothing overnight, gentle by day.';
      case SleepFocus.regularity:
        return 'Emphasize sleep timing and the 7–9 hour range.';
      case SleepFocus.overnightLows:
        return 'Emphasize overnight lows and pre-bed snack ideas.';
      case SleepFocus.lateDinnerHighs:
        return 'Emphasize the dinner-timing coach.';
    }
  }
}

/// Per-user sleep preferences plus the live-capture handshake field.
class SleepSettings {
  const SleepSettings({
    this.targetSleepHours = 8,
    this.targetBedtimeMinutes = 22 * 60 + 30,
    this.reminderEnabled = false,
    this.focus = SleepFocus.balanced,
    this.pendingBedtime,
  });

  /// Target nightly sleep, hours. The report's 7–9h "sweet spot" is the default.
  final int targetSleepHours;

  /// Preferred bedtime as minutes since local midnight (default 22:30).
  final int targetBedtimeMinutes;

  final bool reminderEnabled;

  /// Which nudges the sleep layer emphasizes (S9). Never suppresses safety.
  final SleepFocus focus;

  /// Set when the user has tapped "I'm going to bed" but not yet "I'm awake".
  /// Null the rest of the time.
  final DateTime? pendingBedtime;

  bool get hasPendingBedtime => pendingBedtime != null;

  /// S9 gating: is the dinner-timing coach (S3) allowed to speak?
  bool get showsDinnerCoach =>
      focus == SleepFocus.balanced || focus == SleepFocus.lateDinnerHighs;

  /// S9 gating: is the bedtime-snack advisor (S7) allowed to speak? The
  /// nocturnal-low flag (S8) is safety and is never gated by focus.
  bool get showsSnackAdvisor =>
      focus == SleepFocus.balanced || focus == SleepFocus.overnightLows;

  SleepSettings copyWith({
    int? targetSleepHours,
    int? targetBedtimeMinutes,
    bool? reminderEnabled,
    SleepFocus? focus,
    DateTime? pendingBedtime,
    bool clearPendingBedtime = false,
  }) {
    return SleepSettings(
      targetSleepHours: targetSleepHours ?? this.targetSleepHours,
      targetBedtimeMinutes: targetBedtimeMinutes ?? this.targetBedtimeMinutes,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      focus: focus ?? this.focus,
      pendingBedtime: clearPendingBedtime
          ? null
          : pendingBedtime ?? this.pendingBedtime,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'targetSleepHours': targetSleepHours,
    'targetBedtimeMinutes': targetBedtimeMinutes,
    'reminderEnabled': reminderEnabled,
    'focus': focus.name,
    'pendingBedtime': pendingBedtime == null
        ? null
        : Timestamp.fromDate(pendingBedtime!),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory SleepSettings.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return const SleepSettings();
    return SleepSettings(
      targetSleepHours: (data['targetSleepHours'] as num?)?.toInt() ?? 8,
      targetBedtimeMinutes:
          (data['targetBedtimeMinutes'] as num?)?.toInt() ?? (22 * 60 + 30),
      reminderEnabled: data['reminderEnabled'] as bool? ?? false,
      focus: _enumByName(SleepFocus.values, data['focus'], SleepFocus.balanced),
      pendingBedtime: (data['pendingBedtime'] as Timestamp?)?.toDate(),
    );
  }
}

String _dayId(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

import 'package:cloud_firestore/cloud_firestore.dart';

enum GlucoseSource { libreView, demo }

enum GlucoseRecordType { historic, scan, strip, unknown }

class GlucoseReading {
  const GlucoseReading({
    required this.id,
    required this.timestamp,
    required this.valueMgDl,
    required this.originalValue,
    required this.originalUnit,
    required this.source,
    required this.recordType,
    this.deviceId,
  });

  final String id;
  final DateTime timestamp;
  final double valueMgDl;
  final double originalValue;
  final String originalUnit;
  final GlucoseSource source;
  final GlucoseRecordType recordType;
  final String? deviceId;

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'timestamp': Timestamp.fromDate(timestamp),
    'valueMgDl': valueMgDl,
    'originalValue': originalValue,
    'originalUnit': originalUnit,
    'source': source.name,
    'recordType': recordType.name,
    if (deviceId != null) 'deviceId': deviceId,
  };

  factory GlucoseReading.fromFirestore(Map<String, dynamic> data) {
    return GlucoseReading(
      id: data['id'] as String? ?? '',
      timestamp:
          (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      valueMgDl: (data['valueMgDl'] as num?)?.toDouble() ?? 0,
      originalValue: (data['originalValue'] as num?)?.toDouble() ?? 0,
      originalUnit: data['originalUnit'] as String? ?? 'mg/dL',
      source: _enumByName(
        GlucoseSource.values,
        data['source'],
        GlucoseSource.libreView,
      ),
      recordType: _enumByName(
        GlucoseRecordType.values,
        data['recordType'],
        GlucoseRecordType.unknown,
      ),
      deviceId: data['deviceId'] as String?,
    );
  }
}

class GlucoseSettings {
  const GlucoseSettings({
    this.displayUnit = 'mg/dL',
    this.lowMgDl = 70,
    this.highMgDl = 180,
    this.rangeConfirmed = false,
    this.aiMealGroupingConsent = false,
  });

  final String displayUnit;
  final double lowMgDl;
  final double highMgDl;
  final bool rangeConfirmed;
  final bool aiMealGroupingConsent;

  GlucoseSettings copyWith({
    String? displayUnit,
    double? lowMgDl,
    double? highMgDl,
    bool? rangeConfirmed,
    bool? aiMealGroupingConsent,
  }) {
    return GlucoseSettings(
      displayUnit: displayUnit ?? this.displayUnit,
      lowMgDl: lowMgDl ?? this.lowMgDl,
      highMgDl: highMgDl ?? this.highMgDl,
      rangeConfirmed: rangeConfirmed ?? this.rangeConfirmed,
      aiMealGroupingConsent:
          aiMealGroupingConsent ?? this.aiMealGroupingConsent,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'displayUnit': displayUnit,
    'lowMgDl': lowMgDl,
    'highMgDl': highMgDl,
    'rangeConfirmed': rangeConfirmed,
    'aiMealGroupingConsent': aiMealGroupingConsent,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory GlucoseSettings.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return const GlucoseSettings();
    return GlucoseSettings(
      displayUnit: data['displayUnit'] as String? ?? 'mg/dL',
      lowMgDl: (data['lowMgDl'] as num?)?.toDouble() ?? 70,
      highMgDl: (data['highMgDl'] as num?)?.toDouble() ?? 180,
      rangeConfirmed: data['rangeConfirmed'] as bool? ?? false,
      aiMealGroupingConsent:
          data['aiMealGroupingConsent'] as bool? ?? false,
    );
  }
}

class CgmImportPreview {
  const CgmImportPreview({
    required this.source,
    required this.readings,
    required this.rejectedRows,
    required this.duplicateRows,
    required this.detectedUnit,
    required this.timezoneWasInferred,
    this.deviceId,
  });

  final GlucoseSource source;
  final List<GlucoseReading> readings;
  final int rejectedRows;
  final int duplicateRows;
  final String detectedUnit;
  final bool timezoneWasInferred;
  final String? deviceId;

  DateTime? get startedAt => readings.isEmpty ? null : readings.first.timestamp;
  DateTime? get endedAt => readings.isEmpty ? null : readings.last.timestamp;
}

abstract interface class CgmImporter {
  Future<CgmImportPreview> parse(String content);
}

double glucoseForDisplay(double mgDl, String unit) {
  return unit == 'mmol/L' ? mgDl / 18.0182 : mgDl;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

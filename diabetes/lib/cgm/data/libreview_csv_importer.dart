import 'dart:convert';

import '../models/glucose_models.dart';

class LibreViewCsvImporter implements CgmImporter {
  const LibreViewCsvImporter();

  @override
  Future<CgmImportPreview> parse(String content) async {
    final lines = const LineSplitter().convert(content.replaceFirst('\ufeff', ''));
    if (lines.isEmpty) throw const FormatException('The selected file is empty.');

    var headerIndex = -1;
    var delimiter = ',';
    List<String> headers = const [];
    for (var index = 0; index < lines.length; index++) {
      final candidateDelimiter = _detectDelimiter(lines[index]);
      final fields = _parseRow(lines[index], candidateDelimiter);
      final normalized = fields.map(_normalizeHeader).toList();
      if (normalized.any((value) => value.contains('device timestamp')) &&
          normalized.any((value) => value.contains('record type'))) {
        headerIndex = index;
        delimiter = candidateDelimiter;
        headers = normalized;
        break;
      }
    }
    if (headerIndex < 0) {
      throw const FormatException('This does not look like a LibreView glucose export.');
    }

    final timestampIndex = _findHeader(headers, ['device timestamp', 'timestamp']);
    final recordIndex = _findHeader(headers, ['record type']);
    final historicIndex = _findHeader(headers, ['historic glucose']);
    final scanIndex = _findHeader(headers, ['scan glucose']);
    final stripIndex = _findHeader(headers, ['strip glucose']);
    final serialIndex = _findHeader(headers, ['serial number', 'device']);
    final unit = headers.any((header) => header.contains('mmol/l'))
        ? 'mmol/L'
        : 'mg/dL';

    if (timestampIndex < 0 || recordIndex < 0 ||
        (historicIndex < 0 && scanIndex < 0 && stripIndex < 0)) {
      throw const FormatException('Required LibreView columns are missing.');
    }

    final readings = <GlucoseReading>[];
    final seen = <String>{};
    var rejected = 0;
    var duplicates = 0;
    String? deviceId;
    for (final line in lines.skip(headerIndex + 1)) {
      if (line.trim().isEmpty) continue;
      final row = _parseRow(line, delimiter);
      try {
        final timestamp = _parseTimestamp(_cell(row, timestampIndex));
        final recordNumber = int.tryParse(_cell(row, recordIndex)) ?? -1;
        final type = switch (recordNumber) {
          0 => GlucoseRecordType.historic,
          1 => GlucoseRecordType.scan,
          3 => GlucoseRecordType.strip,
          _ => GlucoseRecordType.unknown,
        };
        final valueText = switch (type) {
          GlucoseRecordType.historic => _cell(row, historicIndex),
          GlucoseRecordType.scan => _cell(row, scanIndex),
          GlucoseRecordType.strip => _cell(row, stripIndex),
          GlucoseRecordType.unknown => '',
        };
        final value = double.tryParse(valueText.replaceAll(',', '.'));
        if (timestamp == null || value == null || value <= 0) {
          rejected++;
          continue;
        }
        deviceId ??= _cell(row, serialIndex).trim().isEmpty
            ? null
            : _cell(row, serialIndex).trim();
        final id = '${deviceId ?? 'libre'}-${timestamp.toUtc().microsecondsSinceEpoch}-${type.name}';
        if (!seen.add(id)) {
          duplicates++;
          continue;
        }
        readings.add(
          GlucoseReading(
            id: id,
            timestamp: timestamp,
            valueMgDl: unit == 'mmol/L' ? value * 18.0182 : value,
            originalValue: value,
            originalUnit: unit,
            source: GlucoseSource.libreView,
            recordType: type,
            deviceId: deviceId,
          ),
        );
      } catch (_) {
        rejected++;
      }
    }
    readings.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (readings.isEmpty) {
      throw const FormatException('No usable glucose readings were found.');
    }
    return CgmImportPreview(
      source: GlucoseSource.libreView,
      readings: readings,
      rejectedRows: rejected,
      duplicateRows: duplicates,
      detectedUnit: unit,
      timezoneWasInferred: false,
      deviceId: deviceId,
    );
  }
}

String _detectDelimiter(String line) {
  return _countOutsideQuotes(line, ';') > _countOutsideQuotes(line, ',')
      ? ';'
      : ',';
}

int _countOutsideQuotes(String value, String character) {
  var quoted = false;
  var count = 0;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (char == '"') quoted = !quoted;
    if (!quoted && char == character) count++;
  }
  return count;
}

List<String> _parseRow(String line, String delimiter) {
  final values = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var index = 0; index < line.length; index++) {
    final char = line[index];
    if (char == '"') {
      if (quoted && index + 1 < line.length && line[index + 1] == '"') {
        buffer.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && char == delimiter) {
      values.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  values.add(buffer.toString().trim());
  return values;
}

String _normalizeHeader(String value) => value.toLowerCase().trim();

int _findHeader(List<String> headers, List<String> needles) {
  return headers.indexWhere(
    (header) => needles.any((needle) => header.contains(needle)),
  );
}

String _cell(List<String> row, int index) {
  return index < 0 || index >= row.length ? '' : row[index];
}

DateTime? _parseTimestamp(String value) {
  final iso = DateTime.tryParse(value);
  if (iso != null) return iso;
  final match = RegExp(
    r'^(\d{1,4})[/-](\d{1,2})[/-](\d{1,4})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null) return null;
  var first = int.parse(match.group(1)!);
  final second = int.parse(match.group(2)!);
  var third = int.parse(match.group(3)!);
  final yearFirst = first > 31;
  final year = yearFirst ? first : third;
  final month = yearFirst
      ? second
      : first > 12
      ? second
      : first;
  final day = yearFirst
      ? third
      : first > 12
      ? first
      : second;
  var hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final secondValue = int.tryParse(match.group(6) ?? '') ?? 0;
  final period = match.group(7)?.toUpperCase();
  if (period == 'PM' && hour < 12) hour += 12;
  if (period == 'AM' && hour == 12) hour = 0;
  try {
    return DateTime(year, month, day, hour, minute, secondValue);
  } catch (_) {
    return null;
  }
}

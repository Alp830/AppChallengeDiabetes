// Offline re-score of saved raw scan outputs against the current
// answer_key.json. No API key, no network, and the ledger is never touched.
//
//   flutter test tool/scan_eval/rescore_test.dart \
//     --dart-define=SCAN_VARIANT=baseline \
//     [--dart-define=RAW_DATE=2026-10-25]
//
// Writes tool/scan_eval/results/<date>-<variant>-rescored.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'ledger.dart' show costUsd;
import 'report.dart';
import 'scorer.dart';

const _variantName = String.fromEnvironment(
  'SCAN_VARIANT',
  defaultValue: 'baseline',
);

/// Optional prefix of the raw file name (its ISO timestamp), e.g. 2026-10-25.
const _rawDate = String.fromEnvironment('RAW_DATE');

const _evalDir = 'tool/scan_eval';

void main() {
  test('rescore raw outputs: $_variantName', () {
    final key = AnswerKey.load('$_evalDir/answer_key.json');
    final rawDir = Directory('$_evalDir/results/raw');
    final files = !rawDir.existsSync()
        ? <File>[]
        : (rawDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.json'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path)));

    final byPhoto = <String, List<EvalRun>>{};
    var used = 0;
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      if (_rawDate.isNotEmpty && !name.startsWith(_rawDate)) continue;
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (raw['variant'] != _variantName) continue;

      final photo = raw['photo'] as String;
      if (!key.photoFiles.containsKey(photo)) {
        fail('$name: unknown photo "$photo"');
      }
      final items = [
        for (final i in raw['items'] as List<dynamic>)
          ScanOutputItem(
            (i as Map<String, dynamic>)['name'] as String,
            alternatives: [
              for (final a in (i['alternatives'] ?? []) as List<dynamic>)
                a as String,
            ],
            confidence: i['confidence'] as String?,
          ),
      ];
      final cost = costUsd(
        promptTokens: (raw['promptTokens'] as num).toInt(),
        outputTokens:
            (raw['candidatesTokens'] as num).toInt() +
            (raw['thoughtsTokens'] as num).toInt(),
      );
      byPhoto
          .putIfAbsent(photo, () => [])
          .add(
            EvalRun.ok(
              (raw['run'] as num).toInt(),
              scorePhoto(key, photo, items),
              Duration(milliseconds: (raw['latencyMs'] as num).toInt()),
              cost,
            ),
          );
      used++;
    }

    if (used == 0) {
      fail(
        'No raw files for variant "$_variantName"'
        '${_rawDate.isEmpty ? '' : ' and date "$_rawDate"'} in ${rawDir.path}',
      );
    }

    // Key order for photos, run order within a photo.
    final results = {
      for (final id in key.photoFiles.keys)
        if (byPhoto.containsKey(id))
          id: (byPhoto[id]!..sort((a, b) => a.run.compareTo(b.run))),
    };
    final report = buildReport(
      title: 'Scan eval (re-scored): $_variantName',
      header: [
        'Re-scored $used saved raw outputs against the current answer key. '
            'No API calls; the ledger was not touched. Cost is computed from '
            'saved token counts.',
      ],
      results: results,
    );
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final out = File('$_evalDir/results/$date-$_variantName-rescored.md')
      ..parent.createSync(recursive: true);
    out.writeAsStringSync(report);
    // ignore: avoid_print
    print('Wrote ${out.path}\n$report');
  });
}

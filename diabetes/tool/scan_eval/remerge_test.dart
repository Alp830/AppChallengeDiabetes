// Offline re-merge of saved per-call scan outputs with the current mergeScans,
// scored against the current answer_key.json. No API key, no network, and the
// ledger is never touched. Raw files without `perCall` are skipped.
//
//   flutter test tool/scan_eval/remerge_test.dart \
//     --dart-define=SCAN_VARIANT=v3-grid \
//     [--dart-define=RAW_DATE=2026-10-25]
//
// Writes tool/scan_eval/results/<date>-<variant>-remerged.md.
import 'dart:convert';
import 'dart:io';

import 'package:diabetes/fridge/scan/scan_merge.dart';
import 'package:diabetes/fridge/scan/scan_models.dart';
import 'package:diabetes/main.dart' show FoodType;
import 'package:flutter_test/flutter_test.dart';

import 'ledger.dart' show costUsd;
import 'report.dart';
import 'scorer.dart';

const _variantName = String.fromEnvironment(
  'SCAN_VARIANT',
  defaultValue: 'v3-grid',
);

/// Optional prefix of the raw file name (its ISO timestamp), e.g. 2026-10-25.
const _rawDate = String.fromEnvironment('RAW_DATE');

const _evalDir = 'tool/scan_eval';

ScannedItem _toScanned(Map<String, dynamic> i) {
  final box = i['box'];
  return ScannedItem(
    name: i['name'] as String,
    foodType: FoodType.other,
    confidence: ScanConfidence.fromLabel(i['confidence']),
    alternatives: [
      for (final a in (i['alternatives'] ?? []) as List<dynamic>) a as String,
    ],
    location: (i['location'] ?? '') as String,
    box2d: box is List ? [for (final v in box) (v as num).toInt()] : null,
  );
}

void main() {
  test('re-merge saved per-call outputs: $_variantName', () {
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
    final counts = <String>[];
    var used = 0;
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      if (_rawDate.isNotEmpty && !name.startsWith(_rawDate)) continue;
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (raw['variant'] != _variantName) continue;
      final perCall = raw['perCall'];
      if (perCall is! List) continue;

      final photo = raw['photo'] as String;
      if (!key.photoFiles.containsKey(photo)) {
        fail('$name: unknown photo "$photo"');
      }
      final lists = [
        for (final call in perCall)
          [
            for (final i in (call as Map<String, dynamic>)['items'] as List)
              _toScanned(i as Map<String, dynamic>),
          ],
      ];
      final unmerged = lists.fold<int>(0, (n, l) => n + l.length);
      final merged = lists.isEmpty
          ? <ScannedItem>[]
          : mergeScans(lists.first, lists.skip(1).toList());
      final score = scorePhoto(key, photo, [
        for (final item in merged)
          ScanOutputItem(
            item.name,
            alternatives: item.alternatives,
            confidence: item.confidence.label,
          ),
      ]);
      final run = (raw['run'] as num).toInt();
      counts.add(
        '- $photo run $run: ${(raw['items'] as List).length} items saved, '
        '$unmerged before merge (${lists.length} calls), '
        '${merged.length} after re-merge, '
        '${score.duplicates.length} duplicates.',
      );
      byPhoto
          .putIfAbsent(photo, () => [])
          .add(
            EvalRun.ok(
              run,
              score,
              Duration(milliseconds: (raw['latencyMs'] as num).toInt()),
              costUsd(
                promptTokens: (raw['promptTokens'] as num).toInt(),
                outputTokens:
                    (raw['candidatesTokens'] as num).toInt() +
                    (raw['thoughtsTokens'] as num).toInt(),
              ),
            ),
          );
      used++;
    }

    if (used == 0) {
      fail(
        'No raw files with perCall for variant "$_variantName"'
        '${_rawDate.isEmpty ? '' : ' and date "$_rawDate"'} in ${rawDir.path}',
      );
    }

    final results = {
      for (final id in key.photoFiles.keys)
        if (byPhoto.containsKey(id))
          id: (byPhoto[id]!..sort((a, b) => a.run.compareTo(b.run))),
    };
    final report = buildReport(
      title: 'Scan eval (re-merged): $_variantName',
      header: [
        'Re-merged $used saved raw outputs with the current mergeScans and '
            're-scored them against the current answer key. No API calls; the '
            'ledger was not touched. Cost is computed from saved token counts.',
        counts.join('\n'),
      ],
      results: results,
    );
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final out = File('$_evalDir/results/$date-$_variantName-remerged.md')
      ..parent.createSync(recursive: true);
    out.writeAsStringSync(report);
    // ignore: avoid_print
    print('Wrote ${out.path}\n$report');
  });
}

// Live fridge-scan eval. It lives in tool/, not test/, so the normal
// `flutter test` never makes a paid call.
//
//   flutter test tool/scan_eval/scan_eval_test.dart \
//     --dart-define=SCAN_VARIANT=baseline \
//     --dart-define=GEMINI_API_KEY=... \
//     [--dart-define=SCAN_PHOTOS=blurry,clear] [--dart-define=SCAN_RUNS=3]
//
// Real HTTP: flutter_test only blocks the network (HttpOverrides answering
// 400) once TestWidgetsFlutterBinding is initialised, which happens in
// testWidgets or an explicit ensureInitialized. This file uses plain test()
// and never touches the binding. HttpOverrides.global is also cleared
// defensively.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'ledger.dart';
import 'report.dart';
import 'scorer.dart';
import 'variants.dart';

const _apiKey = String.fromEnvironment('GEMINI_API_KEY');
const _variantName = String.fromEnvironment(
  'SCAN_VARIANT',
  defaultValue: 'baseline',
);
const _photosArg = String.fromEnvironment('SCAN_PHOTOS');
const _runsArg = String.fromEnvironment('SCAN_RUNS', defaultValue: '3');

const _evalDir = 'tool/scan_eval';

/// Paid model calls one run of each variant makes. A multi-call variant must
/// declare its count here so the budget check reserves for all of them.
const _callsPerRun = <String, int>{
  'baseline': 1,
  'v2-high': 1,
  'v2-ultra': 1,
  'v2-medium': 1,
  'v2-lean': 1,
  'v3-grid': 4,
  'v3-grid-overview': 5,
  'v3-zones': 1 + 4,
  'v3-zoom': 2,
  'v3-grid-zoom': 5,
};

/// Keeps each run's raw output so a scorer or key fix can re-score old runs
/// without paying for new calls.
void _saveRaw(String photo, int run, VariantResult result, Duration latency) {
  final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  File('$_evalDir/results/raw/$stamp-$_variantName-$photo-$run.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'variant': _variantName,
        'photo': photo,
        'run': run,
        'latencyMs': latency.inMilliseconds,
        'promptTokens': result.usage.promptTokenCount,
        'candidatesTokens': result.usage.candidatesTokenCount,
        'thoughtsTokens': result.usage.thoughtsTokenCount,
        if (result.calls != null) 'calls': result.calls,
        if (result.callTimings != null)
          'callTimingsMs': [
            for (final timing in result.callTimings!) timing.inMilliseconds,
          ],
        if (result.perCall != null) 'perCall': result.perCall,
        'items': [
          for (final item in result.items)
            {
              'name': item.name,
              'alternatives': item.alternatives,
              'confidence': item.confidence,
            },
        ],
      }),
    );
}

void main() {
  test(
    'scan eval: $_variantName',
    () async {
      HttpOverrides.global = null;

      final variant = scanVariants[_variantName];
      if (variant == null) {
        fail(
          'Unknown SCAN_VARIANT "$_variantName". '
          'Known: ${scanVariants.keys.join(', ')}',
        );
      }
      final runs = int.tryParse(_runsArg);
      if (runs == null || runs < 1) fail('SCAN_RUNS must be >= 1: "$_runsArg"');
      final callsPerRun = _callsPerRun[_variantName] ?? 1;

      final key = AnswerKey.load('$_evalDir/answer_key.json');
      final photoIds = _photosArg.isEmpty
          ? key.photoFiles.keys.toList()
          : _photosArg.split(',').map((p) => p.trim()).toList();
      for (final id in photoIds) {
        if (!key.photoFiles.containsKey(id)) {
          fail(
            'Unknown photo "$id". Known: ${key.photoFiles.keys.join(', ')}',
          );
        }
      }

      final ledger = Ledger('$_evalDir/results/ledger.json');
      final results = <String, List<EvalRun>>{};
      final notes = <String>[];
      String? refusal;

      photos:
      for (final id in photoIds) {
        final file = File('$_evalDir/${key.photoFiles[id]}');
        if (!file.existsSync()) fail('Photo file missing: ${file.path}');
        final bytes = Uint8List.fromList(file.readAsBytesSync());

        for (var run = 1; run <= runs; run++) {
          // Worst case for every call of this run, against what is already
          // on the books, before any money is spent.
          try {
            ledger.assertBudgetFor(callsPerRun);
          } on StateError catch (error) {
            refusal = error.message;
            notes.add('Stopped before $id run $run: $refusal');
            break photos;
          }

          final watch = Stopwatch()..start();
          try {
            final result = await variant(bytes, apiKey: _apiKey);
            watch.stop();
            // Spend first; a raw-save failure must not lose it or fail the run.
            final saved = recordThenSaveRaw(
              ledger,
              variant: _variantName,
              photo: id,
              run: run,
              promptTokens: result.usage.promptTokenCount,
              outputTokens:
                  result.usage.candidatesTokenCount +
                  result.usage.thoughtsTokenCount,
              saveRaw: () => _saveRaw(id, run, result, watch.elapsed),
            );
            if (saved.rawSaveError != null) {
              notes.add(
                'Raw output NOT saved for $id run $run '
                '(spend was recorded): ${saved.rawSaveError}',
              );
            }
            results
                .putIfAbsent(id, () => [])
                .add(
                  EvalRun.ok(
                    run,
                    scorePhoto(key, id, result.items),
                    watch.elapsed,
                    saved.entry.costUsd,
                  ),
                );
          } catch (error) {
            watch.stop();
            results
                .putIfAbsent(id, () => [])
                .add(EvalRun.failed(run, error.toString(), watch.elapsed));
          }
        }
      }

      final report = buildReport(
        title: 'Scan eval: $_variantName',
        header: [ledgerHeader(ledger)],
        results: results,
        notes: notes,
      );
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final out = File('$_evalDir/results/$date-$_variantName.md')
        ..parent.createSync(recursive: true);
      out.writeAsStringSync(report);
      // ignore: avoid_print
      print('Wrote ${out.path}\n$report');

      if (refusal != null) fail(refusal);
    },
    skip: _apiKey.isEmpty ? 'GEMINI_API_KEY not set; live eval skipped' : false,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

import 'ledger.dart';
import 'scorer.dart';

/// One scored (or failed) run of one photo.
class EvalRun {
  EvalRun.ok(this.run, this.score, this.latency, this.cost) : error = null;
  EvalRun.failed(this.run, this.error, this.latency) : score = null, cost = 0;

  final int run;
  final PhotoScore? score;
  final Duration latency;
  final double cost;
  final String? error;
}

String _pct(double? v) => v == null ? 'n/a' : '${(v * 100).round()}%';

String _recallCell(TierRecall r) =>
    r.total == 0 ? 'n/a' : '${r.hits}/${r.total} (${_pct(r.recall)})';

String _secs(Duration d) => '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';

/// Markdown report shared by the live eval and the offline re-score.
/// [header] lines go under the title (ledger total, or a re-score note);
/// [notes] are listed at the end (refusals, raw-save failures).
String buildReport({
  required String title,
  required List<String> header,
  required Map<String, List<EvalRun>> results,
  List<String> notes = const [],
  DateTime? now,
}) {
  final b = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln('Date: ${(now ?? DateTime.now()).toIso8601String()}');
  for (final line in header) {
    b
      ..writeln()
      ..writeln(line);
  }

  for (final entry in results.entries) {
    final id = entry.key;
    final runs = entry.value;
    final good = runs.where((r) => r.score != null).toList();
    b
      ..writeln()
      ..writeln('## Photo: $id')
      ..writeln()
      ..writeln(
        '${good.length}/${runs.length} runs succeeded.'
        '${id == 'blurry' ? ' Recall counts only items with '
                  'visibleInBlurryPhoto=true.' : ''}',
      )
      ..writeln()
      ..writeln(
        '| run | readable | recognizable | hidden | read+recog | false | '
        'leaks | sure precision | latency | cost |',
      )
      ..writeln('|---|---|---|---|---|---|---|---|---|---|');
    for (final r in runs) {
      final s = r.score;
      if (s == null) {
        b.writeln(
          '| ${r.run} | FAILED: ${r.error!.replaceAll('|', '/').replaceAll('\n', ' ')} '
          '| | | | | | | ${_secs(r.latency)} | \$0 |',
        );
        continue;
      }
      b.writeln(
        '| ${r.run} | ${_recallCell(s.tierRecall['readable']!)} '
        '| ${_recallCell(s.tierRecall['recognizable']!)} '
        '| ${_recallCell(s.tierRecall['hidden']!)} '
        '| ${_recallCell(s.combinedRecall)} '
        '| ${s.falseItems.length} | ${s.leaks.length} '
        '| ${_pct(s.surePrecision)} | ${_secs(r.latency)} '
        '| \$${r.cost.toStringAsFixed(4)} |',
      );
    }

    if (good.isNotEmpty) {
      final scores = [for (final r in good) r.score!];
      String med(double? Function(PhotoScore) f) =>
          _pct(median(scores.map(f).whereType<double>()));
      b
        ..writeln()
        ..writeln('Median recall: ')
        ..writeln(
          '- readable ${med((s) => s.tierRecall['readable']!.recall)}, '
          'recognizable ${med((s) => s.tierRecall['recognizable']!.recall)}, '
          'hidden ${med((s) => s.tierRecall['hidden']!.recall)}, '
          'readable+recognizable ${med((s) => s.combinedRecall.recall)}',
        )
        ..writeln('- sure precision ${med((s) => s.surePrecision)}')
        ..writeln(
          '- false items ${median(scores.map((s) => s.falseItems.length))}, '
          'leaks ${median(scores.map((s) => s.leaks.length))}',
        )
        ..writeln(
          '- latency ${_secs(Duration(milliseconds: median(good.map((r) => r.latency.inMilliseconds))!.round()))}, '
          'cost \$${median(good.map((r) => r.cost))!.toStringAsFixed(4)} per call',
        )
        ..writeln()
        ..writeln('Per run details:');
      for (final r in good) {
        final s = r.score!;
        b
          ..writeln()
          ..writeln('### Run ${r.run}')
          ..writeln('- hits: ${s.hits.join(', ')}')
          ..writeln('- misses: ${s.misses.join(', ')}')
          ..writeln('- false items: ${s.falseItems.join(', ')}')
          ..writeln('- non-food leaks: ${s.leaks.join(', ')}')
          ..writeln('- duplicates: ${s.duplicates.join(', ')}')
          ..writeln('- out of scope (neutral): ${s.outOfScope.join(', ')}');
      }
    }
  }

  if (notes.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Notes')
      ..writeln();
    for (final n in notes) {
      b.writeln('- $n');
    }
  }
  return b.toString();
}

/// Header line for live runs.
String ledgerHeader(Ledger ledger) =>
    'Ledger total spent: \$${ledger.totalSpentUsd.toStringAsFixed(4)} '
    'of \$${budgetCapUsd.toStringAsFixed(2)}';

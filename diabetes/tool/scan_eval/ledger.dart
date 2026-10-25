import 'dart:convert';
import 'dart:io';

/// Argon prices, USD per 1M tokens. Thinking is billed as output.
const inputUsdPerMillion = 2.0;
const outputUsdPerMillion = 10.0;

/// Hard upper bound on one paid call's input tokens (photo plus prompt).
const inputTokenBound = 20000;

/// generationConfig.maxOutputTokens in lib/fridge/scan/fridge_scan_service.dart.
/// Thinking tokens count against it.
const maxOutputTokens = 32768;

/// Worst-case spend of one paid call: every bound reached.
const worstCaseUsdPerCall =
    inputTokenBound * inputUsdPerMillion / 1e6 +
    maxOutputTokens * outputUsdPerMillion / 1e6;

/// Hard cap on total spend recorded in the ledger plus the next run.
const budgetCapUsd = 4.50;

double costUsd({required int promptTokens, required int outputTokens}) =>
    promptTokens * inputUsdPerMillion / 1e6 +
    outputTokens * outputUsdPerMillion / 1e6;

class LedgerEntry {
  const LedgerEntry({
    required this.timestamp,
    required this.variant,
    required this.photo,
    required this.run,
    required this.promptTokens,
    required this.outputTokens,
    required this.costUsd,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
    timestamp: json['timestamp'] as String,
    variant: json['variant'] as String,
    photo: json['photo'] as String,
    run: json['run'] as int,
    promptTokens: json['promptTokens'] as int,
    outputTokens: json['outputTokens'] as int,
    costUsd: (json['costUsd'] as num).toDouble(),
  );

  final String timestamp;
  final String variant;
  final String photo;
  final int run;
  final int promptTokens;

  /// Candidate tokens plus thinking tokens.
  final int outputTokens;
  final double costUsd;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'variant': variant,
    'photo': photo,
    'run': run,
    'promptTokens': promptTokens,
    'outputTokens': outputTokens,
    'costUsd': costUsd,
  };
}

/// Books a successful paid call in [ledger] first, then runs [saveRaw]. A
/// failing [saveRaw] never loses the spend or fails the run: its error text
/// comes back as `rawSaveError` for the report.
({LedgerEntry entry, String? rawSaveError}) recordThenSaveRaw(
  Ledger ledger, {
  required String variant,
  required String photo,
  required int run,
  required int promptTokens,
  required int outputTokens,
  required void Function() saveRaw,
}) {
  final entry = ledger.record(
    variant: variant,
    photo: photo,
    run: run,
    promptTokens: promptTokens,
    outputTokens: outputTokens,
  );
  String? rawSaveError;
  try {
    saveRaw();
  } catch (error) {
    rawSaveError = error.toString();
  }
  return (entry: entry, rawSaveError: rawSaveError);
}

/// Append-only record of every paid call, kept in results/ledger.json.
class Ledger {
  Ledger(this.path) : entries = _read(path);

  final String path;
  final List<LedgerEntry> entries;

  static List<LedgerEntry> _read(String path) {
    final file = File(path);
    if (!file.existsSync()) return [];
    final text = file.readAsStringSync().trim();
    if (text.isEmpty) return [];
    return [
      for (final e in jsonDecode(text) as List<dynamic>)
        LedgerEntry.fromJson(e as Map<String, dynamic>),
    ];
  }

  double get totalSpentUsd => entries.fold(0.0, (sum, e) => sum + e.costUsd);

  /// Throws a [StateError] when spending [calls] more calls at the worst-case
  /// price could take the total past [budgetCapUsd]. Call it before every
  /// paid call (or, for a multi-call variant, before each whole run with that
  /// run's call count).
  void assertBudgetFor(int calls) {
    final estimate = calls * worstCaseUsdPerCall;
    final spent = totalSpentUsd;
    if (spent + estimate > budgetCapUsd) {
      throw StateError(
        'Scan eval refused: spent \$${spent.toStringAsFixed(2)} so far + '
        'worst-case \$${estimate.toStringAsFixed(2)} for $calls calls '
        '(\$${worstCaseUsdPerCall.toStringAsFixed(4)} each) exceeds the '
        '\$${budgetCapUsd.toStringAsFixed(2)} budget. Lower SCAN_RUNS or '
        'SCAN_PHOTOS, or raise budgetCapUsd in ledger.dart on purpose.',
      );
    }
  }

  /// Records one call and saves immediately, so a crash mid-run keeps the
  /// spend on the books.
  LedgerEntry record({
    required String variant,
    required String photo,
    required int run,
    required int promptTokens,
    required int outputTokens,
    DateTime? now,
  }) {
    final entry = LedgerEntry(
      timestamp: (now ?? DateTime.now()).toIso8601String(),
      variant: variant,
      photo: photo,
      run: run,
      promptTokens: promptTokens,
      outputTokens: outputTokens,
      costUsd: costUsd(
        promptTokens: promptTokens,
        outputTokens: outputTokens,
      ),
    );
    entries.add(entry);
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert([
        for (final e in entries) e.toJson(),
      ]),
    );
    return entry;
  }
}

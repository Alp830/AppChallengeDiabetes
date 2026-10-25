import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/scan_eval/ledger.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('scan_ledger_test');
    path = '${dir.path}/results/ledger.json';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Records one call costing exactly [usd] (output tokens only).
  void spend(Ledger ledger, double usd) => ledger.record(
    variant: 'baseline',
    photo: 'clear',
    run: 1,
    promptTokens: 0,
    outputTokens: (usd * 1e6 / outputUsdPerMillion).round(),
  );

  group('worst-case bound per call', () {
    test('is input bound plus maxOutputTokens at list price', () {
      expect(inputTokenBound, 20000);
      expect(maxOutputTokens, 32768);
      expect(worstCaseUsdPerCall, closeTo(0.04 + 0.32768, 1e-9));
    });

    test('one call is allowed while spent + bound stays within the cap', () {
      final ledger = Ledger(path);
      spend(ledger, 4.0);
      expect(() => ledger.assertBudgetFor(1), returnsNormally);
    });

    test('refuses when spent + bound would cross the cap', () {
      final ledger = Ledger(path);
      spend(ledger, 4.2);
      expect(
        () => ledger.assertBudgetFor(1),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('refused'),
          ),
        ),
      );
    });

    test('a multi-call run reserves the bound for every call', () {
      final ledger = Ledger(path);
      spend(ledger, 3.8);
      expect(() => ledger.assertBudgetFor(1), returnsNormally);
      expect(() => ledger.assertBudgetFor(2), throwsStateError);
    });

    test('checking before every call stops before the call that would cross', () {
      final ledger = Ledger(path);
      var calls = 0;
      // Each call spends its full worst case: the most the check must allow.
      while (true) {
        try {
          ledger.assertBudgetFor(1);
        } on StateError {
          break;
        }
        ledger.record(
          variant: 'baseline',
          photo: 'clear',
          run: ++calls,
          promptTokens: inputTokenBound,
          outputTokens: maxOutputTokens,
        );
      }
      expect(calls, (budgetCapUsd / worstCaseUsdPerCall).floor());
      expect(ledger.totalSpentUsd, lessThanOrEqualTo(budgetCapUsd));
      expect(
        ledger.totalSpentUsd + worstCaseUsdPerCall,
        greaterThan(budgetCapUsd),
      );
    });
  });

  group('recordThenSaveRaw', () {
    test('the spend is on disk before the raw save runs', () {
      final ledger = Ledger(path);
      var entriesWhenSaving = -1;
      var onDiskWhenSaving = -1;
      final saved = recordThenSaveRaw(
        ledger,
        variant: 'baseline',
        photo: 'clear',
        run: 1,
        promptTokens: 1000,
        outputTokens: 500,
        saveRaw: () {
          entriesWhenSaving = ledger.entries.length;
          onDiskWhenSaving = Ledger(path).entries.length;
        },
      );
      expect(entriesWhenSaving, 1);
      expect(onDiskWhenSaving, 1);
      expect(saved.rawSaveError, isNull);
      expect(saved.entry.costUsd, closeTo(0.002 + 0.005, 1e-9));
    });

    test('a failing raw save keeps the spend and does not throw', () {
      final ledger = Ledger(path);
      final saved = recordThenSaveRaw(
        ledger,
        variant: 'baseline',
        photo: 'clear',
        run: 1,
        promptTokens: 1000,
        outputTokens: 500,
        saveRaw: () => throw const FileSystemException('disk full'),
      );
      expect(saved.rawSaveError, contains('disk full'));
      expect(Ledger(path).entries, hasLength(1));
      expect(ledger.totalSpentUsd, closeTo(0.007, 1e-9));
    });
  });
}

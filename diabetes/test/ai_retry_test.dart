import 'dart:async';

import 'package:diabetes/ai/ai_retry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the loop asked to wait for, and never actually waits, so the
/// tests stay instant even though the real policy sleeps 2 s.
class _FakeSleeper {
  final List<Duration> slept = [];
  Future<void> Function()? onSleep;

  Future<void> call(Duration duration) async {
    slept.add(duration);
    await onSleep?.call();
  }
}

void main() {
  group('isRetryableAiError', () {
    test('temporary HTTP statuses are retryable, permanent ones are not', () {
      for (final status in const [408, 429, 500, 502, 503, 504]) {
        expect(
          isRetryableAiError(AiRequestException.fromStatus(status, 'body')),
          isTrue,
          reason: 'status $status',
        );
      }
      for (final status in const [400, 401, 403, 404]) {
        expect(
          isRetryableAiError(AiRequestException.fromStatus(status, 'body')),
          isFalse,
          reason: 'status $status',
        );
      }
    });

    test('timeouts, bad JSON and socket failures are retryable', () {
      expect(isRetryableAiError(TimeoutException('slow')), isTrue);
      expect(isRetryableAiError(const FormatException('bad json')), isTrue);
      expect(
        isRetryableAiError(Exception('SocketException: Failed host lookup')),
        isTrue,
      );
      expect(isRetryableAiError(Exception('ClientException: broke')), isTrue);
      expect(isRetryableAiError(Exception('Connection closed')), isTrue);
    });

    test('a 429 for a used-up quota is not retried, a rate limit is', () {
      const noTier =
          '{"error":{"code":429,"message":"Quota exceeded for metric: '
          'generate_content_free_tier_requests, limit: 0, model: gemini-4-argon"}}';
      const perDay =
          '{"error":{"code":429,"details":[{"quotaId":'
          '"GenerateRequestsPerDayPerProjectPerModel-FreeTier"}]}}';
      const perMinute =
          '{"error":{"code":429,"details":[{"quotaId":'
          '"GenerateRequestsPerMinutePerProjectPerModel"}]}}';

      expect(isRetryableResponse(429, noTier), isFalse);
      expect(isRetryableResponse(429, perDay), isFalse);
      expect(isRetryableResponse(429, perMinute), isTrue);
      expect(
        isRetryableAiError(AiRequestException.fromStatus(429, noTier)),
        isFalse,
      );
      // Only a 429 reads the body; a 503 that happens to say "PerDay" retries.
      expect(isRetryableResponse(503, perDay), isTrue);
    });

    test('cancellation and a missing key never retry', () {
      expect(isRetryableAiError(const AiCancelledException()), isFalse);
      expect(
        isRetryableAiError(
          const AiRequestException('Missing GEMINI_API_KEY', retryable: false),
        ),
        isFalse,
      );
      expect(isRetryableAiError(StateError('nope')), isFalse);
    });
  });

  group('runWithAbortableAiRetry', () {
    test('a timed-out attempt is aborted before the next one starts', () async {
      final aborted = <int>[];
      var calls = 0;

      final value = await runWithAbortableAiRetry<String>(
        (abort) {
          final number = ++calls;
          abort.then((_) => aborted.add(number));
          if (number == 1) return Completer<String>().future; // hangs
          return Future.value('ok');
        },
        policy: const AiRetryPolicy(attemptTimeout: Duration(milliseconds: 10)),
        sleep: (_) async {},
      );
      await Future<void>.delayed(Duration.zero);

      expect(value, 'ok');
      expect(calls, 2);
      // Attempt 1 by its timeout; attempt 2 once it settled.
      expect(aborted, [1, 2]);
    });

    test('cancelling aborts the attempt in flight', () async {
      final cancellation = AiCancellation();
      final abortSeen = Completer<void>();

      final run = runWithAbortableAiRetry<String>(
        (abort) async {
          await abort;
          abortSeen.complete();
          throw Exception('ClientException: Request aborted');
        },
        cancellation: cancellation,
        sleep: (_) async {},
      );
      cancellation.cancel();

      await expectLater(run, throwsA(isA<AiCancelledException>()));
      expect(abortSeen.isCompleted, isTrue);
    });
  });

  group('runWithAiRetry', () {
    test('succeeds on attempt 3 after two 2 s waits', () async {
      final sleeper = _FakeSleeper();
      final attempts = <int>[];
      final maxes = <int>[];
      var calls = 0;

      final value = await runWithAiRetry<String>(
        () async {
          calls++;
          if (calls < 3) throw AiRequestException.fromStatus(503, 'busy');
          return 'ok';
        },
        cancellation: AiCancellation(),
        onAttempt: (attempt, maxAttempts) {
          attempts.add(attempt);
          maxes.add(maxAttempts);
        },
        sleep: sleeper.call,
      );

      expect(value, 'ok');
      expect(calls, 3);
      expect(attempts, [1, 2, 3]);
      expect(maxes, [5, 5, 5]);
      expect(sleeper.slept, const [Duration(seconds: 2), Duration(seconds: 2)]);
    });

    test('gives up after five attempts and throws the last error', () async {
      final sleeper = _FakeSleeper();
      var calls = 0;

      await expectLater(
        runWithAiRetry<String>(() async {
          calls++;
          throw AiRequestException.fromStatus(503, 'busy $calls');
        }, sleep: sleeper.call),
        throwsA(
          isA<AiRequestException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.message, 'message', contains('503')),
        ),
      );
      expect(calls, 5);
      expect(sleeper.slept, hasLength(4));
    });

    test('a 400 fails on the first attempt', () async {
      final sleeper = _FakeSleeper();
      var calls = 0;

      await expectLater(
        runWithAiRetry<String>(() async {
          calls++;
          throw AiRequestException.fromStatus(400, 'bad request');
        }, sleep: sleeper.call),
        throwsA(isA<AiRequestException>()),
      );
      expect(calls, 1);
      expect(sleeper.slept, isEmpty);
    });

    test('a missing API key fails on the first attempt', () async {
      final sleeper = _FakeSleeper();
      var calls = 0;

      await expectLater(
        runWithAiRetry<String>(() async {
          calls++;
          throw const AiRequestException(
            'Missing GEMINI_API_KEY',
            retryable: false,
          );
        }, sleep: sleeper.call),
        throwsA(isA<AiRequestException>()),
      );
      expect(calls, 1);
    });

    test('an empty or unparseable reply is retried', () async {
      final sleeper = _FakeSleeper();
      var calls = 0;

      final value = await runWithAiRetry<String>(() async {
        calls++;
        if (calls == 1) throw const FormatException('no candidates');
        return 'ok';
      }, sleep: sleeper.call);

      expect(value, 'ok');
      expect(calls, 2);
    });

    test('cancelling during the wait stops the loop', () async {
      final cancellation = AiCancellation();
      final sleeper = _FakeSleeper()
        ..onSleep = () async => cancellation.cancel();
      var calls = 0;

      await expectLater(
        runWithAiRetry<String>(
          () async {
            calls++;
            throw AiRequestException.fromStatus(503, 'busy');
          },
          cancellation: cancellation,
          sleep: sleeper.call,
        ),
        throwsA(isA<AiCancelledException>()),
      );
      expect(calls, 1, reason: 'no attempt runs after cancel');
    });

    test('cancelling before the first attempt runs nothing', () async {
      var calls = 0;
      await expectLater(
        runWithAiRetry<String>(() async {
          calls++;
          return 'ok';
        }, cancellation: AiCancellation()..cancel()),
        throwsA(isA<AiCancelledException>()),
      );
      expect(calls, 0);
    });

    test('an attempt that outruns attemptTimeout is retried', () async {
      final sleeper = _FakeSleeper();
      var calls = 0;

      final value = await runWithAiRetry<String>(
        () async {
          calls++;
          if (calls == 1) return Completer<String>().future; // never completes
          return 'ok';
        },
        policy: const AiRetryPolicy(attemptTimeout: Duration(milliseconds: 20)),
        sleep: sleeper.call,
      );

      expect(value, 'ok');
      expect(calls, 2);
    });

    test('attempts never overlap', () async {
      final sleeper = _FakeSleeper();
      var inFlight = 0;
      var maxInFlight = 0;
      var calls = 0;

      await runWithAiRetry<String>(() async {
        inFlight++;
        maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        calls++;
        inFlight--;
        if (calls < 3) throw AiRequestException.fromStatus(500, 'oops');
        return 'ok';
      }, sleep: sleeper.call);

      expect(maxInFlight, 1);
    });

    test('maxAttempts and delay are configurable', () async {
      final sleeper = _FakeSleeper();
      var calls = 0;

      await expectLater(
        runWithAiRetry<String>(
          () async {
            calls++;
            throw AiRequestException.fromStatus(503, 'busy');
          },
          policy: const AiRetryPolicy(
            maxAttempts: 2,
            delay: Duration(milliseconds: 500),
          ),
          sleep: sleeper.call,
        ),
        throwsA(isA<AiRequestException>()),
      );
      expect(calls, 2);
      expect(sleeper.slept, const [Duration(milliseconds: 500)]);
    });
  });
}

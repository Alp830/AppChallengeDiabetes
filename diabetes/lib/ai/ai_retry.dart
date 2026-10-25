/// The single place that decides how often a Gemini call is retried, how long
/// it waits between tries, and which failures are worth trying again at all.
///
/// The fridge scan, the meal recommendation, and the Q&A answer all go through
/// [runWithAiRetry], so "5 attempts, 2 s apart" is stated once.
///
/// `dart:io` is deliberately not imported — `lib/` has to compile for web, so
/// `SocketException` is recognised by its string form in [isRetryableAiError].
library;

import 'dart:async';

/// Implemented by any feature-specific failure that already knows whether it
/// is worth another attempt (`AiRequestException`, `MealQaException`). Keeps
/// [isRetryableAiError] from having to import every feature's error type.
abstract interface class RetryableAiError {
  bool get retryable;

  /// The HTTP status behind the failure, when there was one.
  int? get statusCode;
}

/// Typed failure for Gemini calls so the retry rule can tell a temporary
/// hiccup from a request that will never succeed.
class AiRequestException implements Exception, RetryableAiError {
  const AiRequestException(
    this.message, {
    this.statusCode,
    required this.retryable,
  });

  /// A non-2xx reply. Only the transient statuses are worth another attempt;
  /// 400/401/403/404 mean the request itself is wrong.
  factory AiRequestException.fromStatus(int status, String body) =>
      AiRequestException(
        'Gemini request failed: $status',
        statusCode: status,
        retryable: isRetryableResponse(status, body),
      );

  final String message;
  @override
  final int? statusCode;
  @override
  final bool retryable;

  @override
  String toString() => message;
}

/// Thrown when the user cancelled, closed the sheet, or left the screen.
class AiCancelledException implements Exception {
  const AiCancelledException();

  @override
  String toString() => 'AiCancelledException';
}

/// Lets the screen stop a retry loop when the user leaves or cancels.
class AiCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes on [cancel], so an attempt in flight can abort its request
  /// instead of running on after the user has gone.
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// How many times to try, how long to wait between tries, and how long one
/// attempt may take. The per-attempt timeout differs per call site (scan 90 s,
/// recommendation 45 s, Q&A answer 30 s).
class AiRetryPolicy {
  const AiRetryPolicy({
    this.maxAttempts = 5,
    this.delay = const Duration(seconds: 2),
    this.attemptTimeout,
  });

  final int maxAttempts;
  final Duration delay;
  final Duration? attemptTimeout;
}

/// The HTTP statuses that mean "busy or broken right now", as opposed to
/// "this request is wrong".
bool isRetryableStatus(int status) =>
    const {408, 429, 500, 502, 503, 504}.contains(status);

/// [isRetryableStatus], except a 429 that means the quota is used up rather
/// than "slow down". `limit: 0` is a model this key's tier can't use at all
/// (Argon has no free tier) and a per-day quota doesn't refill in 2 s, so
/// five attempts would only make the user wait for the same refusal.
bool isRetryableResponse(int status, String body) {
  if (!isRetryableStatus(status)) return false;
  if (status != 429) return true;
  return !(body.contains('limit: 0') || body.contains('PerDay'));
}

/// True when trying the very same request again could plausibly work.
bool isRetryableAiError(Object error) {
  if (error is AiCancelledException) return false;
  if (error is RetryableAiError) return error.retryable;
  if (error is TimeoutException) return true;
  // An empty or unparseable model reply: the next roll of the dice may be fine.
  if (error is FormatException) return true;
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection closed');
}

/// Runs [attempt] up to `policy.maxAttempts` times, waiting `policy.delay`
/// between tries.
///
/// [onAttempt] fires before each attempt (1-based) so the UI can show
/// `Retrying 2/5`. Throws the last error once the attempts run out, or
/// [AiCancelledException] as soon as [cancellation] is cancelled.
///
/// A timed-out attempt is only abandoned, not stopped: `Future.timeout` leaves
/// the HTTP call running. Callers that can abort their request should use
/// [runWithAbortableAiRetry] instead.
Future<T> runWithAiRetry<T>(
  Future<T> Function() attempt, {
  AiRetryPolicy policy = const AiRetryPolicy(),
  AiCancellation? cancellation,
  void Function(int attempt, int maxAttempts)? onAttempt,
  Future<void> Function(Duration) sleep = Future.delayed,
}) => runWithAbortableAiRetry(
  (_) => attempt(),
  policy: policy,
  cancellation: cancellation,
  onAttempt: onAttempt,
  sleep: sleep,
);

/// [runWithAiRetry], but each attempt gets an `abort` future that completes
/// when the loop gives up on it: its timeout fired, or [cancellation] was
/// cancelled. Pass it to `http.AbortableRequest` so a slow attempt is really
/// stopped, which keeps attempts from overlapping and from being billed twice.
/// `abort` also completes once the attempt has settled; that is harmless for
/// a finished request.
Future<T> runWithAbortableAiRetry<T>(
  Future<T> Function(Future<void> abort) attempt, {
  AiRetryPolicy policy = const AiRetryPolicy(),
  AiCancellation? cancellation,
  void Function(int attempt, int maxAttempts)? onAttempt,
  Future<void> Function(Duration) sleep = Future.delayed,
}) async {
  for (var number = 1; ; number++) {
    if (cancellation?.isCancelled ?? false) throw const AiCancelledException();
    onAttempt?.call(number, policy.maxAttempts);

    final abort = Completer<void>();
    void abortAttempt() {
      if (!abort.isCompleted) abort.complete();
    }

    cancellation?.whenCancelled.then((_) => abortAttempt());
    try {
      final timeout = policy.attemptTimeout;
      final future = attempt(abort.future);
      return timeout == null
          ? await future
          : await future.timeout(
              timeout,
              onTimeout: () {
                abortAttempt();
                throw TimeoutException('AI attempt timed out', timeout);
              },
            );
    } catch (error) {
      if (cancellation?.isCancelled ?? false) {
        throw const AiCancelledException();
      }
      if (number >= policy.maxAttempts || !isRetryableAiError(error)) rethrow;
    } finally {
      abortAttempt();
    }

    await sleep(policy.delay);
    if (cancellation?.isCancelled ?? false) throw const AiCancelledException();
  }
}

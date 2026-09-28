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

/// Typed failure for Gemini calls so the retry rule can tell a temporary
/// hiccup from a request that will never succeed.
class AiRequestException implements Exception {
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
        retryable: const {408, 429, 500, 502, 503, 504}.contains(status),
      );

  final String message;
  final int? statusCode;
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
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
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

/// True when trying the very same request again could plausibly work.
bool isRetryableAiError(Object error) {
  if (error is AiCancelledException) return false;
  if (error is AiRequestException) return error.retryable;
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
/// `Retrying 2/5`. Attempts never overlap: the next one starts only after the
/// previous future has settled. Throws the last error once the attempts run
/// out, or [AiCancelledException] as soon as [cancellation] is cancelled.
Future<T> runWithAiRetry<T>(
  Future<T> Function() attempt, {
  AiRetryPolicy policy = const AiRetryPolicy(),
  AiCancellation? cancellation,
  void Function(int attempt, int maxAttempts)? onAttempt,
  Future<void> Function(Duration) sleep = Future.delayed,
}) async {
  for (var number = 1; ; number++) {
    if (cancellation?.isCancelled ?? false) throw const AiCancelledException();
    onAttempt?.call(number, policy.maxAttempts);

    try {
      final timeout = policy.attemptTimeout;
      final future = attempt();
      return timeout == null ? await future : await future.timeout(timeout);
    } catch (error) {
      if (cancellation?.isCancelled ?? false) {
        throw const AiCancelledException();
      }
      if (number >= policy.maxAttempts || !isRetryableAiError(error)) rethrow;
    }

    await sleep(policy.delay);
    if (cancellation?.isCancelled ?? false) throw const AiCancelledException();
  }
}

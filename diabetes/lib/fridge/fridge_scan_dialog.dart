import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../ai/ai_retry.dart';
import '../ai/ai_retry_status.dart';
import '../design/app_radius.dart';
import '../design/friendly_errors.dart';
import '../design/spacing.dart';
import '../main.dart' show FoodItem;

/// Outcome of a fridge photo scan. The dialog returns null when cancelled or
/// closed after a failure — a failure is reported inside the dialog now, so
/// [FridgeScanResult.failure] is only a safety net for callers.
class FridgeScanResult {
  const FridgeScanResult.success(this.foods) : error = null;
  const FridgeScanResult.failure(Object this.error) : foods = const [];

  final List<FoodItem> foods;
  final Object? error;
}

/// Blocks the fridge while the AI scan runs (5–15 s per attempt), so the user
/// sees progress, can cancel, and can't edit a grid that's about to change.
///
/// A scan is the most expensive AI call in the app and the easiest to lose:
/// the user has already framed and taken the photo. So a failure keeps the
/// photo on screen and offers `Try again` rather than dropping them back on
/// the grid with a snackbar.
class FridgeScanDialog extends StatefulWidget {
  const FridgeScanDialog({
    super.key,
    required this.imageBytes,
    required this.detect,
    this.retryPolicy = const AiRetryPolicy(
      // The scan thinks at level high, so one attempt is genuinely slow.
      attemptTimeout: Duration(seconds: 90),
    ),
  });

  final Uint8List imageBytes;
  final Future<List<FoodItem>> Function(Uint8List imageBytes) detect;
  final AiRetryPolicy retryPolicy;

  @override
  State<FridgeScanDialog> createState() => _FridgeScanDialogState();
}

class _FridgeScanDialogState extends State<FridgeScanDialog> {
  final _cancellation = AiCancellation();
  int _attempt = 1;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    // Assigned directly rather than through setState: the first run starts
    // from initState, where there is nothing to rebuild yet.
    if (_error != null || _attempt != 1) {
      setState(() {
        _error = null;
        _attempt = 1;
      });
    }

    try {
      final foods = await runWithAiRetry(
        () => widget.detect(widget.imageBytes),
        policy: widget.retryPolicy,
        cancellation: _cancellation,
        onAttempt: (attempt, _) {
          if (!mounted || attempt == _attempt) return;
          setState(() => _attempt = attempt);
        },
      );
      if (!mounted || _cancellation.isCancelled) return;
      Navigator.of(context).pop(FridgeScanResult.success(foods));
    } on AiCancelledException {
      return;
    } catch (error) {
      if (!mounted || _cancellation.isCancelled) return;
      setState(() => _error = error);
    }
  }

  void _cancel() {
    _cancellation.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;

    return PopScope(
      // Back is blocked while work is in flight, but once it has failed there
      // is nothing left to protect.
      canPop: error != null,
      child: AlertDialog(
        // The photo plus the message runs past a 360x780 phone at 2x text.
        scrollable: true,
        title: Text(
          error == null ? 'Finding foods…' : "Couldn't read the photo",
        ),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Opacity(
                  opacity: 0.6,
                  child: Image.memory(
                    widget.imageBytes,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(height: 160),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.s16),
              if (error == null) ...[
                const LinearProgressIndicator(),
                AiRetryStatus(
                  attempt: _attempt,
                  maxAttempts: widget.retryPolicy.maxAttempts,
                ),
                const SizedBox(height: Spacing.s12),
                Text(
                  'This usually takes 5–15 seconds.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else
                Text(
                  FriendlyErrors.ai(error, action: 'a read of your photo'),
                  style: theme.textTheme.bodyMedium,
                ),
            ],
          ),
        ),
        actions: error == null
            ? [
                TextButton(
                  key: const Key('fridgeScanCancel'),
                  onPressed: _cancel,
                  child: const Text('Cancel'),
                ),
              ]
            : [
                TextButton(
                  key: const Key('fridgeScanClose'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                FilledButton(
                  key: const Key('fridgeScanTryAgain'),
                  onPressed: _run,
                  child: const Text('Try again'),
                ),
              ],
      ),
    );
  }
}

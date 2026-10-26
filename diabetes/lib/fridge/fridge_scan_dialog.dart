import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../ai/ai_retry.dart';
import '../ai/ai_retry_status.dart';
import '../design/app_radius.dart';
import '../design/friendly_errors.dart';
import '../design/spacing.dart';
import '../main.dart' show FoodItem;
import 'scan/fridge_scan_pipeline.dart' show ScanProgress;

/// Outcome of a fridge photo scan. The dialog returns null when cancelled or
/// closed after a failure — a failure is reported inside the dialog now, so
/// [FridgeScanResult.failure] is only a safety net for callers.
class FridgeScanResult {
  const FridgeScanResult.success(this.foods) : error = null;
  const FridgeScanResult.failure(Object this.error) : foods = const [];

  final List<FoodItem> foods;
  final Object? error;
}

/// Blocks the fridge while the AI scan runs (about 30 s per attempt), so the
/// user sees progress, can cancel, and can't edit a grid that's about to change.
///
/// A scan is the most expensive AI call in the app and the easiest to lose:
/// the user has already framed and taken the photo. So a failure keeps the
/// photo on screen and offers `Try again` rather than dropping them back on
/// the grid with a snackbar.
class FridgeScanDialog extends StatefulWidget {
  const FridgeScanDialog({
    super.key,
    required this.imageBytes,
    this.detect,
    this.detectWithProgress,
    this.retryPolicy = const AiRetryPolicy(
      // Measured: one lean call takes ~27 s on a 1080p photo, and a 2×2 tile
      // grid 33–39 s on a 24 MP one (the full v2 prompt took 87 s there). So
      // 120 s is a hung request, not a slow one. Attempts are aborted, not
      // left running.
      attemptTimeout: Duration(seconds: 120),
    ),
  }) : assert(
         (detect == null) != (detectWithProgress == null),
         'Pass exactly one of detect and detectWithProgress',
       );

  final Uint8List imageBytes;

  /// [abort] completes when the retry loop gives up on this attempt; pass it
  /// on to the request so it is really stopped.
  final Future<List<FoodItem>> Function(
    Uint8List imageBytes,
    Future<void> abort,
  )?
  detect;

  /// [detect], plus a sink for live progress: call [onProgress] as the scan
  /// streams in items, and the dialog shows them.
  final Future<List<FoodItem>> Function(
    Uint8List imageBytes,
    Future<void> abort,
    void Function(ScanProgress progress) onProgress,
  )?
  detectWithProgress;
  final AiRetryPolicy retryPolicy;

  @override
  State<FridgeScanDialog> createState() => _FridgeScanDialogState();
}

class _FridgeScanDialogState extends State<FridgeScanDialog> {
  final _cancellation = AiCancellation();
  int _attempt = 1;
  Object? _error;
  ScanProgress? _progress;

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
        _progress = null;
      });
    }

    try {
      final foods = await runWithAbortableAiRetry(
        (abort) {
          final withProgress = widget.detectWithProgress;
          if (withProgress == null) {
            return widget.detect!(widget.imageBytes, abort);
          }
          return withProgress(widget.imageBytes, abort, (progress) {
            if (!mounted || _cancellation.isCancelled) return;
            setState(() => _progress = progress);
          });
        },
        policy: widget.retryPolicy,
        cancellation: _cancellation,
        onAttempt: (attempt, _) {
          if (!mounted || attempt == _attempt) return;
          setState(() {
            _attempt = attempt;
            _progress = null;
          });
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
                if (_progress case final progress?)
                  _ProgressText(progress: progress)
                else
                  Text(
                    'This usually takes about 30 seconds.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ] else
                Text(
                  FriendlyErrors.ai(error, action: 'the foods from your photo'),
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

/// The live part of the dialog: how many items have streamed in, the newest
/// names, and which part of a split photo is being read.
class _ProgressText extends StatelessWidget {
  const _ProgressText({required this.progress});

  final ScanProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final count = progress.itemsSoFar;
    final part = progress.callsTotal > 1
        ? (progress.callsDone + 1).clamp(1, progress.callsTotal)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (count > 0) ...[
          // A live region, so a screen reader announces the count as it grows.
          Semantics(
            key: const Key('fridgeScanProgressCount'),
            liveRegion: true,
            child: Text(
              count == 1 ? 'Found 1 item so far…' : 'Found $count items so far…',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (progress.latestNames.isNotEmpty)
            Text(
              progress.latestNames.join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
        ] else
          Text(
            'This usually takes about 30 seconds.',
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        if (part != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.s4),
            child: Text(
              'Reading part $part of ${progress.callsTotal}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
      ],
    );
  }
}

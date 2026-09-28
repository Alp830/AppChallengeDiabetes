import 'package:flutter/material.dart';

import '../design/spacing.dart';

/// Tells the user the app is still trying, and how many tries are left.
///
/// Attempt 1 renders nothing: a first try is just "loading", and a counter on
/// it would make an ordinary wait look like a failure. From attempt 2 on, the
/// count is what keeps the extra ~10 s of waiting from feeling like a hang.
class AiRetryStatus extends StatelessWidget {
  const AiRetryStatus({
    super.key,
    required this.attempt,
    required this.maxAttempts,
  });

  final int attempt;
  final int maxAttempts;

  @override
  Widget build(BuildContext context) {
    if (attempt < 2) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Semantics(
      key: const Key('aiRetryStatus'),
      liveRegion: true,
      label: 'Retrying, attempt $attempt of $maxAttempts',
      // The row's own text would otherwise be read as "Retrying 2/5", which a
      // screen reader pronounces as a fraction.
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.s8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: Spacing.s8),
            // Flexible, not fixed: at 2x text "Retrying 3/5" is wider than a
            // 360 px phone leaves beside the spinner.
            Flexible(
              child: Text(
                'Retrying $attempt/$maxAttempts',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_theme.dart';
import '../design/spacing.dart';
import '../design/text_scale.dart';

/// First thing a brand-new account sees on Home: a one-tap route to a first
/// meal idea. It says up front that the fridge can stay empty, because the
/// most common first-run question is "do I have to add food first?".
///
/// Same shape and gradient as the fridge banner below it, so it reads as part
/// of the same Home page rather than a pop-up.
class FirstMealCard extends StatelessWidget {
  const FirstMealCard({super.key, required this.onStart, required this.onSkip});

  final VoidCallback onStart;
  final VoidCallback onSkip;

  static const _steps = [
    'Tell us what you feel like',
    'Pick a meal type',
    'Tap Recommend a meal',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onBanner = theme.colorScheme.onPrimary;
    final largeText = useLargeTextLayout(context);

    final actions = [
      FilledButton.icon(
        key: const Key('firstMealStart'),
        onPressed: onStart,
        style: FilledButton.styleFrom(
          backgroundColor: onBanner,
          foregroundColor: theme.colorScheme.primary,
        ),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Show me how'),
      ),
      TextButton(
        key: const Key('firstMealSkip'),
        onPressed: onSkip,
        style: TextButton.styleFrom(
          foregroundColor: onBanner,
          minimumSize: const Size(48, 48),
        ),
        child: const Text('Skip'),
      ),
    ];

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.colorScheme.primary, AppTheme.brandDark],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Let's get started",
                style: theme.textTheme.titleMedium?.copyWith(color: onBanner),
              ),
              const SizedBox(height: Spacing.s4),
              Text(
                'Get your first meal idea in under a minute. No need to fill '
                'your fridge first.',
                style: theme.textTheme.bodyMedium?.copyWith(color: onBanner),
              ),
              const SizedBox(height: Spacing.s12),
              for (var index = 0; index < _steps.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.s8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 24,
                        width: 24,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.only(right: Spacing.s12),
                        decoration: BoxDecoration(
                          color: onBanner.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: onBanner,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _steps[index],
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: onBanner,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Spacing.s4),
              if (largeText)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final action in actions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.s8),
                        child: action,
                      ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(child: actions.first),
                    const SizedBox(width: Spacing.s8),
                    actions.last,
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

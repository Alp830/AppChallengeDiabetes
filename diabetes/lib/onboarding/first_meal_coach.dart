import 'package:flutter/material.dart';

import '../design/app_motion.dart';
import '../design/app_radius.dart';
import '../design/spacing.dart';

/// Coach card above the prompt field on the user's first visit to Meals. It
/// names the three controls in the order they're used, so the example prompt
/// waiting in the field doesn't look like something that already ran.
class FirstMealCoachCard extends StatelessWidget {
  const FirstMealCoachCard({
    super.key,
    required this.onSkipTour,
    this.fridgeIsEmpty = false,
  });

  final VoidCallback onSkipTour;

  /// Adds a line explaining that an empty fridge is fine.
  final bool fridgeIsEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: const Key('firstMealCoach'),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.s16,
          Spacing.s16,
          Spacing.s16,
          Spacing.s8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: Spacing.s8),
                Expanded(
                  child: Text(
                    'Your first meal idea',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.s8),
            Text(
              'We filled in an example. Change it if you like, pick a meal '
              'type, then tap Recommend a meal.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
            if (fridgeIsEmpty) ...[
              const SizedBox(height: Spacing.s8),
              Text(
                "Your fridge is empty, so we'll suggest pantry basics.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('firstMealSkipTour'),
                onPressed: onSkipTour,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSecondaryContainer,
                  minimumSize: const Size(48, 48),
                ),
                child: const Text('Skip tour'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws attention to the button the coach card just named. The outline
/// pulses gently, and holds still when the user asked for reduced motion.
class FirstMealSpotlight extends StatefulWidget {
  const FirstMealSpotlight({super.key, required this.child});

  final Widget child;

  @override
  State<FirstMealSpotlight> createState() => _FirstMealSpotlightState();
}

class _FirstMealSpotlightState extends State<FirstMealSpotlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
      return _outlined(color, 1, child: widget.child);
    }
    return AnimatedBuilder(
      animation: CurvedAnimation(parent: _controller, curve: AppMotion.enter),
      builder: (context, child) =>
          _outlined(color, 0.45 + 0.55 * _controller.value, child: child!),
      child: widget.child,
    );
  }

  Widget _outlined(Color color, double opacity, {required Widget child}) {
    return Container(
      key: const Key('firstMealSpotlight'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md + 3),
        border: Border.all(
          color: color.withValues(alpha: opacity.clamp(0, 1)),
          width: 3,
        ),
      ),
      child: child,
    );
  }
}

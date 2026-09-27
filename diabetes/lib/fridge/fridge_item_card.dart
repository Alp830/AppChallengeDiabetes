import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_status_colors.dart';
import '../design/spacing.dart';
import '../design/text_scale.dart';
import '../main.dart' show FoodItem;
import 'freshness.dart';

/// Compact inventory tile. Tapping edits the item (delete lives in the edit
/// sheet), and in selection mode tapping toggles selection.
class FridgeItemCard extends StatelessWidget {
  const FridgeItemCard({
    super.key,
    required this.foodItem,
    required this.onEdit,
    this.selected = false,
    this.selectionMode = false,
    this.onToggleSelection,
    this.now,
  });

  final FoodItem foodItem;
  final VoidCallback onEdit;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onToggleSelection;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final freshness = freshnessFor(foodItem.expiryDate, now: now);
    final statusColor = AppStatusColors.of(context).forFreshness(freshness);
    final statusTint = AppStatusColors.tint(statusColor);

    final scheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.4)
            : scheme.surface,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selectionMode ? onToggleSelection : onEdit,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.s8,
                  vertical: Spacing.s8,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 36,
                        width: 36,
                        decoration: BoxDecoration(
                          color: statusTint,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Icon(
                          foodItem.foodType.icon,
                          size: 20,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(height: Spacing.s4),
                      Text(
                        foodItem.name,
                        textAlign: TextAlign.center,
                        maxLines: useLargeTextLayout(context) ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: Spacing.s4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusTint,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          freshness.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (selectionMode)
                Positioned(
                  top: Spacing.s4,
                  left: Spacing.s4,
                  child: Semantics(
                    container: true,
                    label: selected ? 'Selected' : 'Not selected',
                    child: ExcludeSemantics(
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 22,
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

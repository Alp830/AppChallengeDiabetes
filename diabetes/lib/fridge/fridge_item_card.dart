import 'package:flutter/material.dart';

import '../design/app_status_colors.dart';
import '../design/spacing.dart';
import '../main.dart' show FoodItem;
import 'freshness.dart';

/// Compact inventory tile. Tapping the body edits the item; the close control
/// removes it without forcing every card to reserve space for full metadata.
class FridgeItemCard extends StatelessWidget {
  const FridgeItemCard({
    super.key,
    required this.foodItem,
    required this.onEdit,
    required this.onRemove,
    this.selected = false,
    this.selectionMode = false,
    this.onToggleSelection,
    this.now,
  });

  final FoodItem foodItem;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
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
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selectionMode ? onToggleSelection : onEdit,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.s8,
                  vertical: Spacing.s4,
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
                          borderRadius: BorderRadius.circular(12),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusTint,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          freshness.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Icon(
                    Icons.check_circle,
                    size: 20,
                    color: theme.colorScheme.primary,
                    semanticLabel: 'Selected',
                  ),
                )
              else
                Positioned(
                  top: 0,
                  right: 0,
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      key: ValueKey('fridgeDelete_${foodItem.name}'),
                      padding: EdgeInsets.zero,
                      iconSize: 17,
                      tooltip: 'Delete item',
                      visualDensity: VisualDensity.compact,
                      onPressed: onRemove,
                      icon: const Icon(Icons.close),
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

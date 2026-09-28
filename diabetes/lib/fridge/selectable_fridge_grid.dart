import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/drag_selection_surface.dart';
import '../design/app_radius.dart';
import '../design/spacing.dart';
import '../design/text_scale.dart';
import '../main.dart' show FoodItem, FoodType;
import 'fridge_item_card.dart';

enum FoodBulkAction {
  addToMeal('Add selected foods to a meal', Icons.restaurant),
  delete('Delete selected items', Icons.delete_outline);

  const FoodBulkAction(this.label, this.icon);
  final String label;
  final IconData icon;
}

class SelectableFridgeGrid extends StatefulWidget {
  const SelectableFridgeGrid({
    super.key,
    required this.items,
    required this.onEdit,
    required this.onRemoveSelected,
    required this.onBulkAction,
    this.onDelete,
    this.onSelectionCountChanged,
    this.bottomPadding = 144,
  });

  final List<MapEntry<int, FoodItem>> items;
  final ValueChanged<int> onEdit;
  final Future<void> Function(Set<int>) onRemoveSelected;
  final Future<void> Function(FoodBulkAction, List<FoodItem>) onBulkAction;

  /// Staged single-item delete from the tile's own delete button.
  final ValueChanged<int>? onDelete;

  /// Reports how many items are currently selected so the host can make room
  /// for the bottom selection toolbar (e.g. lifting its floating buttons).
  final ValueChanged<int>? onSelectionCountChanged;

  /// Space kept clear below the grid for the host's floating buttons and bars.
  final double bottomPadding;

  @override
  State<SelectableFridgeGrid> createState() => _SelectableFridgeGridState();
}

class _SelectableFridgeGridState extends State<SelectableFridgeGrid> {
  final _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  Set<int> _selected = {};
  bool _selectionMode = false;
  int _lastEmittedCount = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Notifies the host of selection-count changes after the frame, so a parent
  /// setState never runs during this widget's build.
  void _emitSelectionCount() {
    final callback = widget.onSelectionCountChanged;
    if (callback == null) return;
    final count = _selected.length;
    if (count == _lastEmittedCount) return;
    _lastEmittedCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback(count);
    });
  }

  @override
  void didUpdateWidget(covariant SelectableFridgeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final available = widget.items.map((item) => item.key).toSet();
    _itemKeys.removeWhere((key, _) => !available.contains(key));
    final retained = _selected.intersection(available);
    if (!setEquals(retained, _selected)) _selected = retained;
  }

  List<FoodItem> get _selectedFoods => widget.items
      .where((entry) => _selected.contains(entry.key))
      .map((entry) => entry.value)
      .toList();

  Future<void> _runAction(FoodBulkAction action) async {
    if (action == FoodBulkAction.delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            _selected.length == 1
                ? 'Delete 1 item?'
                : 'Delete ${_selected.length} items?',
          ),
          content: const Text(
            'This removes the selected foods from your fridge.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: Text(
                _selected.length == 1
                    ? 'Delete 1 item'
                    : 'Delete ${_selected.length} items',
              ),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        final deleting = Set<int>.of(_selected);
        setState(() {
          _selected = {};
          _selectionMode = false;
        });
        await widget.onRemoveSelected(deleting);
      }
      return;
    }
    await widget.onBulkAction(action, _selectedFoods);
  }

  void _toggle(int index) {
    setState(() {
      _selectionMode = true;
      if (!_selected.add(index)) _selected.remove(index);
    });
  }

  bool get _addModifierPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  /// Tile height from the real text metrics, so names and pills never clip.
  double _tileExtent(BuildContext context, bool largeText) {
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style) =>
        scaler.scale(style.fontSize!) * (style.height ?? 1.2);
    return Spacing.s8 *
            2 // card vertical padding
            +
        4 // selected card's 2px border consumes 2px top and bottom
        +
        1 // float rounding slack in text line-height math
        +
        36 +
        Spacing
            .s4 // icon tile + gap
            +
        line(textTheme.bodyMedium!) * (largeText ? 2 : 1) +
        Spacing.s4 +
        line(textTheme.labelMedium!) +
        Spacing.s4; // pill text + its padding
  }

  /// Buckets the (already expiry-sorted) items by food type, in `FoodType`
  /// declaration order. Empty types are skipped and the incoming order is
  /// kept inside each bucket, so expiry ranking still reads top to bottom.
  List<MapEntry<FoodType, List<MapEntry<int, FoodItem>>>> get _groups {
    final buckets = <FoodType, List<MapEntry<int, FoodItem>>>{};
    for (final entry in widget.items) {
      buckets.putIfAbsent(entry.value.foodType, () => []).add(entry);
    }
    return [
      for (final foodType in FoodType.values)
        if (buckets[foodType] case final group?) MapEntry(foodType, group),
    ];
  }

  Widget _groupHeader(BuildContext context, FoodType foodType, int count) {
    final theme = Theme.of(context);
    return Semantics(
      key: Key('fridgeGroupHeader_${foodType.name}'),
      header: true,
      label: count == 1
          ? '${foodType.label}, 1 item'
          : '${foodType.label}, $count items',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(foodType.icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: Spacing.s8),
            Flexible(
              child: Text(
                foodType.label,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Spacing.s8),
            Text(
              '$count',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final largeText = useLargeTextLayout(context);
    final keys = <int, GlobalKey>{
      for (final entry in widget.items)
        entry.key: _itemKeys.putIfAbsent(entry.key, GlobalKey.new),
    };
    final groups = _groups;

    _emitSelectionCount();

    return DragSelectionSurface<int>(
      itemKeys: keys,
      selectedItems: _selected,
      touchDragEnabled: _selectionMode,
      onSelectionChanged: (selection) => setState(() {
        _selected = selection;
        if (selection.isNotEmpty) _selectionMode = true;
      }),
      scrollController: _scrollController,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.margin,
                  Spacing.margin,
                  Spacing.margin,
                  Spacing.s8,
                ),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          widget.items.length == 1
                              ? '1 item'
                              : '${widget.items.length} items',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.s12,
                          vertical: Spacing.s8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sort,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: Spacing.s4),
                            Text(
                              'Expiry',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (
                var groupIndex = 0;
                groupIndex < groups.length;
                groupIndex++
              ) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    Spacing.margin,
                    groupIndex == 0 ? Spacing.s8 : Spacing.s16,
                    Spacing.margin,
                    Spacing.s8,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _groupHeader(
                      context,
                      groups[groupIndex].key,
                      groups[groupIndex].value.length,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    Spacing.margin,
                    0,
                    Spacing.margin,
                    groupIndex == groups.length - 1 ? widget.bottomPadding : 0,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: largeText ? 180 : 125,
                      mainAxisSpacing: Spacing.s12,
                      crossAxisSpacing: Spacing.s12,
                      mainAxisExtent: _tileExtent(context, largeText),
                    ),
                    delegate: SliverChildBuilderDelegate((context, position) {
                      final entry = groups[groupIndex].value[position];
                      return KeyedSubtree(
                        key: keys[entry.key],
                        child: FridgeItemCard(
                          foodItem: entry.value,
                          selected: _selected.contains(entry.key),
                          selectionMode: _selectionMode,
                          onToggleSelection: () => _toggle(entry.key),
                          onEdit: () {
                            if (_addModifierPressed) {
                              _toggle(entry.key);
                            } else {
                              widget.onEdit(entry.key);
                            }
                          },
                          onDelete: widget.onDelete == null
                              ? null
                              : () => widget.onDelete!(entry.key),
                        ),
                      );
                    }, childCount: groups[groupIndex].value.length),
                  ),
                ),
              ],
            ],
          ),
          // Full-width selection toolbar pinned to the bottom of the screen.
          // The Fridge page lifts its camera/add buttons while this is showing.
          if (_selected.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                elevation: 8,
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.s8,
                      Spacing.s8,
                      Spacing.s16,
                      Spacing.s8,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Cancel selection',
                          onPressed: () => setState(() {
                            _selected = {};
                            _selectionMode = false;
                          }),
                          icon: const Icon(Icons.close),
                        ),
                        Expanded(
                          child: Text(
                            '${_selected.length} selected',
                            style: Theme.of(context).textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton.outlined(
                          key: const Key('deleteSelectedFridgeItems'),
                          tooltip: 'Remove selected',
                          onPressed: () => _runAction(FoodBulkAction.delete),
                          style: IconButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                        const SizedBox(width: Spacing.s8),
                        FilledButton.icon(
                          key: const Key('addSelectedToMeal'),
                          onPressed: () => _runAction(FoodBulkAction.addToMeal),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          icon: const Icon(Icons.restaurant),
                          label: const Text('Add to meal'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

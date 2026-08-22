import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/drag_selection_surface.dart';
import '../design/spacing.dart';
import '../main.dart' show FoodItem;
import 'fridge_item_card.dart';

enum FoodBulkAction {
  addToMeal('Add selected foods to a meal', Icons.restaurant),
  compareCarbs('Compare carbohydrates', Icons.compare_arrows),
  totalCarbs('Calculate total carbohydrates', Icons.calculate),
  totalCalories('Calculate total calories', Icons.local_fire_department),
  saveMeal('Save as a reusable meal', Icons.bookmark_add),
  groceryList('Add to grocery list', Icons.shopping_cart),
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
    this.onSelectionCountChanged,
  });

  final List<MapEntry<int, FoodItem>> items;
  final ValueChanged<int> onEdit;
  final Future<void> Function(Set<int>) onRemoveSelected;
  final Future<void> Function(FoodBulkAction, List<FoodItem>) onBulkAction;

  /// Reports how many items are currently selected so the host can make room
  /// for the bottom selection toolbar (e.g. lifting its floating buttons).
  final ValueChanged<int>? onSelectionCountChanged;

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
          title: Text('Delete ${_selected.length} items?'),
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
              child: const Text('Delete'),
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

  @override
  Widget build(BuildContext context) {
    final keys = <int, GlobalKey>{
      for (final entry in widget.items)
        entry.key: _itemKeys.putIfAbsent(entry.key, GlobalKey.new),
    };

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
                          borderRadius: BorderRadius.circular(999),
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
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.margin,
                  0,
                  Spacing.margin,
                  280,
                ),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 125,
                    mainAxisSpacing: Spacing.s12,
                    crossAxisSpacing: Spacing.s12,
                    childAspectRatio: 0.95,
                  ),
                  delegate: SliverChildBuilderDelegate((context, position) {
                    final entry = widget.items[position];
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
                        onRemove: () => widget.onRemoveSelected({entry.key}),
                      ),
                    );
                  }, childCount: widget.items.length),
                ),
              ),
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
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _runAction(FoodBulkAction.addToMeal),
                          icon: const Icon(Icons.restaurant),
                          label: const Text('Meal'),
                        ),
                        const SizedBox(width: Spacing.s8),
                        FilledButton.icon(
                          key: const Key('deleteSelectedFridgeItems'),
                          onPressed: () => _runAction(FoodBulkAction.delete),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.errorContainer,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                          icon: const Icon(Icons.delete_outline, size: 20),
                          label: const Text('Remove'),
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

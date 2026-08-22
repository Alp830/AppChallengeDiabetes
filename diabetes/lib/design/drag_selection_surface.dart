import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Adds mobile long-press drag selection around an existing scrollable item
/// surface. Desktop mouse marquee selection was intentionally removed — on
/// pointer devices it felt clunky; Ctrl/Shift-click multi-select covers
/// desktop instead.
class DragSelectionSurface<T extends Object> extends StatefulWidget {
  const DragSelectionSurface({
    super.key,
    required this.child,
    required this.itemKeys,
    required this.selectedItems,
    required this.onSelectionChanged,
    required this.scrollController,
    this.touchDragEnabled = false,
    this.onEmptyTap,
  });

  final Widget child;
  final Map<T, GlobalKey> itemKeys;
  final Set<T> selectedItems;
  final ValueChanged<Set<T>> onSelectionChanged;
  final ScrollController scrollController;
  final bool touchDragEnabled;
  final VoidCallback? onEmptyTap;

  @override
  State<DragSelectionSurface<T>> createState() =>
      _DragSelectionSurfaceState<T>();
}

class _DragSelectionSurfaceState<T extends Object>
    extends State<DragSelectionSurface<T>> {
  Offset? _start;
  Offset? _current;
  Set<T> _baseSelection = {};
  bool _additive = false;
  Timer? _autoScrollTimer;

  bool get _dragging => _start != null && _current != null;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  Offset _local(Offset global) =>
      (context.findRenderObject()! as RenderBox).globalToLocal(global);

  Rect? _itemRect(GlobalKey key) {
    final itemContext = key.currentContext;
    final surface = context.findRenderObject();
    final item = itemContext?.findRenderObject();
    if (surface is! RenderBox || item is! RenderBox || !item.attached) {
      return null;
    }
    final topLeft = surface.globalToLocal(item.localToGlobal(Offset.zero));
    return topLeft & item.size;
  }

  bool _overItem(Offset point) => widget.itemKeys.values.any((key) {
    final rect = _itemRect(key);
    return rect != null && rect.contains(point);
  });

  void _begin(Offset position, {required bool additive}) {
    _autoScrollTimer?.cancel();
    setState(() {
      _start = position;
      _current = position;
      _additive = additive;
      _baseSelection = additive ? Set.of(widget.selectedItems) : <T>{};
    });
    _updateSelection();
  }

  void _move(Offset position, {bool autoScroll = false}) {
    if (!_dragging) return;
    setState(() => _current = position);
    _updateSelection();
    if (autoScroll) _updateAutoScroll(position);
  }

  void _finish() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    if (!_dragging) return;
    setState(() {
      _start = null;
      _current = null;
    });
  }

  void _updateSelection() {
    if (!_dragging) return;
    // A stationary long-press still selects the card under the finger.
    final marquee = Rect.fromPoints(_start!, _current!).inflate(1);
    final hits = <T>{};
    for (final entry in widget.itemKeys.entries) {
      final itemRect = _itemRect(entry.value);
      if (itemRect != null && marquee.overlaps(itemRect)) hits.add(entry.key);
    }
    widget.onSelectionChanged({if (_additive) ..._baseSelection, ...hits});
  }

  void _updateAutoScroll(Offset pointer) {
    final height = (context.findRenderObject()! as RenderBox).size.height;
    final direction = pointer.dy < 64
        ? -1.0
        : pointer.dy > height - 64
        ? 1.0
        : 0.0;
    if (direction == 0 || !widget.scrollController.hasClients) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
      return;
    }
    if (_autoScrollTimer != null) return;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 32), (_) {
      if (!mounted || !_dragging || !widget.scrollController.hasClients) return;
      final position = widget.scrollController.position;
      final next = (position.pixels + direction * 5).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      widget.scrollController.jumpTo(next);
      _updateSelection();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final marquee = _dragging ? Rect.fromPoints(_start!, _current!) : null;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        if (!_overItem(details.localPosition)) {
          widget.onSelectionChanged(<T>{});
          widget.onEmptyTap?.call();
        }
      },
      onPanStart: widget.touchDragEnabled
          ? (details) => _begin(details.localPosition, additive: true)
          : null,
      onPanUpdate: widget.touchDragEnabled
          ? (details) => _move(details.localPosition, autoScroll: true)
          : null,
      onPanEnd: widget.touchDragEnabled ? (_) => _finish() : null,
      onPanCancel: widget.touchDragEnabled ? _finish : null,
      onLongPressStart: (details) {
        HapticFeedback.selectionClick();
        _begin(
          _local(details.globalPosition),
          additive: widget.selectedItems.isNotEmpty,
        );
      },
      onLongPressMoveUpdate: (details) =>
          _move(_local(details.globalPosition), autoScroll: true),
      onLongPressEnd: (_) => _finish(),
      child: SelectionContainer.disabled(
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (marquee != null)
              Positioned.fromRect(
                rect: marquee,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      border: Border.all(color: scheme.primary, width: 1.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

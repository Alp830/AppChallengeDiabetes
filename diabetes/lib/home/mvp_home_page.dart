import 'package:flutter/material.dart';

import '../exercise/data/today_todo_repository.dart';

class MvpHomePage extends StatefulWidget {
  const MvpHomePage({
    super.key,
    required this.userId,
    required this.onOpenFridge,
    this.userName,
    this.now,
    this.todoRepository,
    this.todoStateStream,
    this.onSaveTodos,
  });

  final String userId;
  final String? userName;
  final VoidCallback onOpenFridge;
  final DateTime? now;
  final TodayTodoRepository? todoRepository;
  final Stream<TodayTodoState>? todoStateStream;
  final Future<void> Function(List<TodayTodo> items)? onSaveTodos;

  @override
  State<MvpHomePage> createState() => _MvpHomePageState();
}

class _MvpHomePageState extends State<MvpHomePage> {
  late final DateTime _today = widget.now ?? DateTime.now();
  late final TodayTodoRepository? _repository = widget.todoStateStream == null
      ? widget.todoRepository ?? TodayTodoRepository()
      : widget.todoRepository;
  late final Stream<TodayTodoState> _todoState =
      widget.todoStateStream ?? _repository!.watchTodos(widget.userId, _today);
  late final Future<void> Function(List<TodayTodo>) _saveTodos =
      widget.onSaveTodos ??
      (items) => _repository!.saveTodos(widget.userId, _today, items);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TodayTodoState>(
      stream: _todoState,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load your home screen.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return _HomeContent(
          userName: widget.userName,
          today: _today,
          initialItems: snapshot.data!.items,
          onOpenFridge: widget.onOpenFridge,
          onSaveTodos: _saveTodos,
        );
      },
    );
  }
}

class _HomeContent extends StatefulWidget {
  const _HomeContent({
    required this.userName,
    required this.today,
    required this.initialItems,
    required this.onOpenFridge,
    required this.onSaveTodos,
  });

  final String? userName;
  final DateTime today;
  final List<TodayTodo> initialItems;
  final VoidCallback onOpenFridge;
  final Future<void> Function(List<TodayTodo>) onSaveTodos;

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  late List<TodayTodo> _items = List.of(widget.initialItems);
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _HomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialItems != widget.initialItems) {
      _items = List.of(widget.initialItems);
    }
  }

  Future<void> _commit(List<TodayTodo> next) async {
    final previous = _items;
    setState(() {
      _items = next;
      _saving = true;
    });
    try {
      await widget.onSaveTodos(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your checklist.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _taskName([String? current]) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(current == null ? 'Add a task' : 'Edit task'),
        content: TextField(
          key: const Key('mvpTodoNameField'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Task name'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _add() async {
    final name = await _taskName();
    if (name == null) return;
    await _commit([
      ..._items,
      TodayTodo(
        id: 'todo-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final completed = _items.where((item) => item.isCompleted).length;
    return ListView(
      key: const Key('mvpHomePage'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Text(
          _formattedDate(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        _FridgeBanner(onOpenFridge: widget.onOpenFridge),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Text(
                "Today's checklist",
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (_items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '$completed/${_items.length}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            IconButton.filledTonal(
              key: const Key('mvpAddTodoButton'),
              onPressed: _saving ? null : _add,
              tooltip: 'Add task',
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_items.isEmpty)
          _EmptyChecklist(onAdd: _saving ? null : _add)
        else
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
              child: CheckboxListTile(
                value: item.isCompleted,
                title: GestureDetector(
                  onLongPress: _saving
                      ? null
                      : () async {
                          final name = await _taskName(item.name);
                          if (name == null) return;
                          await _commit([
                            for (final current in _items)
                              current.id == item.id
                                  ? current.copyWith(name: name)
                                  : current,
                          ]);
                        },
                  child: Text(item.name),
                ),
                secondary: IconButton(
                  tooltip: 'Remove ${item.name}',
                  onPressed: _saving
                      ? null
                      : () => _commit([
                          for (final current in _items)
                            if (current.id != item.id) current,
                        ]),
                  icon: const Icon(Icons.delete_outline),
                ),
                onChanged: _saving
                    ? null
                    : (value) => _commit([
                        for (final current in _items)
                          current.id == item.id
                              ? current.copyWith(isCompleted: value ?? false)
                              : current,
                      ]),
              ),
            ),
            ),
      ],
    );
  }

  String _formattedDate() {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final date = widget.today;
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }
}

/// Eye-catching gradient entry point into the fridge feature.
class _FridgeBanner extends StatelessWidget {
  const _FridgeBanner({required this.onOpenFridge});

  final VoidCallback onOpenFridge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenFridge,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.primary.withValues(alpha: 0.78)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.kitchen_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "What's in your fridge",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Snap a photo or pick foods to get recipes.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyChecklist extends StatelessWidget {
  const _EmptyChecklist({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            children: [
              Icon(
                Icons.checklist_rounded,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text('No tasks yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Tap + to add your first task for today.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

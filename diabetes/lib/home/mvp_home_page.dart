import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_theme.dart';
import '../design/load_error.dart';
import '../design/spacing.dart';
import '../exercise/data/today_todo_repository.dart';
import '../meals/saved/saved_recipe.dart';
import '../meals/saved/saved_recipes_repository.dart';
import '../onboarding/first_meal_card.dart';

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
    this.fridgeItemCount,
    this.expiringCount = 0,
    this.showFirstMealGuide = false,
    this.onStartFirstMeal,
    this.onSkipFirstMeal,
    this.savedRecipesStore,
    this.onOpenSavedRecipes,
  });

  final String userId;
  final String? userName;
  final VoidCallback onOpenFridge;
  final DateTime? now;
  final TodayTodoRepository? todoRepository;
  final Stream<TodayTodoState>? todoStateStream;
  final Future<void> Function(List<TodayTodo> items)? onSaveTodos;

  /// Fridge size for the banner; null while the fridge is still loading.
  final int? fridgeItemCount;

  /// Items expired or expiring within `kExpiringSoonThresholdDays`.
  final int expiringCount;

  /// Whether this account still has its first-meal guide waiting. New
  /// accounts only; it disappears for good once used or skipped.
  final bool showFirstMealGuide;

  /// Opens Meals with the first-meal guide switched on.
  final VoidCallback? onStartFirstMeal;

  /// Dismisses the guide for good.
  final VoidCallback? onSkipFirstMeal;

  /// Feeds the "Saved recipes" card's count and preview. Null hides nothing:
  /// the card still appears when [onOpenSavedRecipes] is set.
  final SavedRecipesStore? savedRecipesStore;

  /// Opens the saved recipes list. Null hides the card.
  final VoidCallback? onOpenSavedRecipes;

  @override
  State<MvpHomePage> createState() => _MvpHomePageState();
}

class _MvpHomePageState extends State<MvpHomePage> {
  late final DateTime _today = widget.now ?? DateTime.now();
  late final TodayTodoRepository? _repository = widget.todoStateStream == null
      ? widget.todoRepository ?? TodayTodoRepository()
      : widget.todoRepository;
  late Stream<TodayTodoState> _todoState = _watch();
  late final Future<void> Function(List<TodayTodo>) _saveTodos =
      widget.onSaveTodos ??
      (items) => _repository!.saveTodos(widget.userId, _today, items);

  Stream<TodayTodoState> _watch() =>
      widget.todoStateStream ?? _repository!.watchTodos(widget.userId, _today);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TodayTodoState>(
      stream: _todoState,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: LoadErrorView(
              message: "Couldn't load your checklist.",
              onRetry: () => setState(() => _todoState = _watch()),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const _HomeSkeleton();
        }

        return _HomeContent(
          userName: widget.userName,
          today: _today,
          initialItems: snapshot.data!.items,
          onOpenFridge: widget.onOpenFridge,
          onSaveTodos: _saveTodos,
          fridgeItemCount: widget.fridgeItemCount,
          expiringCount: widget.expiringCount,
          showFirstMealGuide: widget.showFirstMealGuide,
          onStartFirstMeal: widget.onStartFirstMeal,
          onSkipFirstMeal: widget.onSkipFirstMeal,
          userId: widget.userId,
          savedRecipesStore: widget.savedRecipesStore,
          onOpenSavedRecipes: widget.onOpenSavedRecipes,
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
    required this.fridgeItemCount,
    required this.expiringCount,
    required this.showFirstMealGuide,
    required this.onStartFirstMeal,
    required this.onSkipFirstMeal,
    required this.userId,
    required this.savedRecipesStore,
    required this.onOpenSavedRecipes,
  });

  final String? userName;
  final DateTime today;
  final List<TodayTodo> initialItems;
  final VoidCallback onOpenFridge;
  final Future<void> Function(List<TodayTodo>) onSaveTodos;
  final int? fridgeItemCount;
  final int expiringCount;
  final bool showFirstMealGuide;
  final VoidCallback? onStartFirstMeal;
  final VoidCallback? onSkipFirstMeal;
  final String userId;
  final SavedRecipesStore? savedRecipesStore;
  final VoidCallback? onOpenSavedRecipes;

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

  Future<bool> _commit(List<TodayTodo> next) async {
    final previous = _items;
    setState(() {
      _items = next;
      _saving = true;
    });
    try {
      await widget.onSaveTodos(next);
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() => _items = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't save your checklist. Try again."),
        ),
      );
      return false;
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

  Future<void> _rename(TodayTodo item) async {
    final name = await _taskName(item.name);
    if (name == null) return;
    await _commit([
      for (final current in _items)
        current.id == item.id ? current.copyWith(name: name) : current,
    ]);
  }

  /// Deletes immediately and offers Undo, instead of a confirmation dialog
  /// (NN/g: undo beats "Are you sure?" for frequent, reversible actions).
  Future<void> _remove(TodayTodo item) async {
    final index = _items.indexWhere((current) => current.id == item.id);
    final saved = await _commit([
      for (final current in _items)
        if (current.id != item.id) current,
    ]);
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed "${item.name}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _commit(
              List.of(_items)..insert(index.clamp(0, _items.length), item),
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final completed = _items.where((item) => item.isCompleted).length;
    return ListView(
      key: const Key('mvpHomePage'),
      padding: const EdgeInsets.fromLTRB(
        Spacing.s16,
        Spacing.s12,
        Spacing.s16,
        Spacing.s24,
      ),
      children: [
        Text(
          MaterialLocalizations.of(context).formatFullDate(widget.today),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: Spacing.s16),
        if (widget.showFirstMealGuide &&
            widget.onStartFirstMeal != null &&
            widget.onSkipFirstMeal != null) ...[
          FirstMealCard(
            onStart: widget.onStartFirstMeal!,
            onSkip: widget.onSkipFirstMeal!,
          ),
          const SizedBox(height: Spacing.s12),
        ],
        _FridgeBanner(
          onOpenFridge: widget.onOpenFridge,
          itemCount: widget.fridgeItemCount,
          expiringCount: widget.expiringCount,
        ),
        if (widget.onOpenSavedRecipes != null) ...[
          const SizedBox(height: Spacing.s12),
          _SavedRecipesCard(
            userId: widget.userId,
            store: widget.savedRecipesStore,
            onOpen: widget.onOpenSavedRecipes!,
          ),
        ],
        const SizedBox(height: Spacing.section),
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
                padding: const EdgeInsets.only(right: Spacing.s4),
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
        const SizedBox(height: Spacing.s12),
        if (_items.isEmpty)
          _EmptyChecklist(onAdd: _saving ? null : _add)
        else
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.s8),
              child: Card(
                child: ListTile(
                  leading: Semantics(
                    label: item.name,
                    child: Checkbox(
                      value: item.isCompleted,
                      onChanged: _saving
                          ? null
                          : (value) => _commit([
                              for (final current in _items)
                                current.id == item.id
                                    ? current.copyWith(
                                        isCompleted: value ?? false,
                                      )
                                    : current,
                            ]),
                    ),
                  ),
                  title: Text(
                    item.name,
                    style: item.isCompleted
                        ? TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: scheme.onSurfaceVariant,
                          )
                        : null,
                  ),
                  onTap: _saving ? null : () => _rename(item),
                  trailing: IconButton(
                    tooltip: 'Remove ${item.name}',
                    onPressed: _saving ? null : () => _remove(item),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// Eye-catching gradient entry point into the fridge feature.
class _FridgeBanner extends StatelessWidget {
  const _FridgeBanner({
    required this.onOpenFridge,
    required this.itemCount,
    required this.expiringCount,
  });

  final VoidCallback onOpenFridge;
  final int? itemCount;
  final int expiringCount;

  String get _summary {
    final count = itemCount;
    if (count == null) return 'Snap a photo or pick foods to get recipes.';
    if (count == 0) return 'Empty — scan a photo to get started.';
    final items = count == 1 ? '1 item' : '$count items';
    return expiringCount == 0
        ? '$items, all fresh'
        : '$items · $expiringCount expiring soon';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onBanner = theme.colorScheme.onPrimary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenFridge,
        child: Ink(
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
            child: Row(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: onBanner.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    Icons.kitchen_outlined,
                    color: onBanner,
                    size: 28,
                  ),
                ),
                const SizedBox(width: Spacing.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "What's in your fridge",
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: onBanner,
                        ),
                      ),
                      const SizedBox(height: Spacing.s4),
                      Text(
                        _summary,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onBanner,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: onBanner),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Entry point to the recipes the user kept, with a preview so the card says
/// something even before it is tapped.
class _SavedRecipesCard extends StatelessWidget {
  const _SavedRecipesCard({
    required this.userId,
    required this.store,
    required this.onOpen,
  });

  final String userId;
  final SavedRecipesStore? store;
  final VoidCallback onOpen;

  String _subtitle(List<SavedRecipe>? saved) {
    if (saved == null || saved.isEmpty) {
      return 'Save recipes from Meals to cook them again';
    }
    final count = saved.length == 1 ? '1 saved' : '${saved.length} saved';
    final names = saved.take(2).map((item) => item.recipe.dishName).join(', ');
    return saved.length > 2 ? '$count · $names, …' : '$count · $names';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: InkWell(
        key: const Key('homeSavedRecipes'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.s16),
          child: StreamBuilder<List<SavedRecipe>>(
            stream: store?.watchAll(userId),
            builder: (context, snapshot) => Row(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    Icons.bookmark_outline,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: Spacing.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Saved recipes', style: theme.textTheme.titleMedium),
                      const SizedBox(height: Spacing.s4),
                      Text(
                        _subtitle(snapshot.data),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: scheme.onSurfaceVariant),
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
          padding: const EdgeInsets.symmetric(
            vertical: Spacing.s24,
            horizontal: Spacing.s16,
          ),
          child: Column(
            children: [
              Icon(
                Icons.checklist_rounded,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: Spacing.s12),
              Text('No tasks yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.s4),
              Text(
                'Add your first task for today.',
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

/// Checklist-shaped placeholder shown while Home loads.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final block = Theme.of(context).colorScheme.surfaceContainerHigh;
    Widget box(double height, {double? width, double radius = AppRadius.md}) =>
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            height: height,
            width: width,
            decoration: BoxDecoration(
              color: block,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        );
    return Semantics(
      label: 'Loading your checklist',
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            Spacing.s16,
            Spacing.s12,
            Spacing.s16,
            Spacing.s24,
          ),
          children: [
            box(16, width: 180),
            const SizedBox(height: Spacing.s16),
            box(80, radius: AppRadius.lg),
            const SizedBox(height: Spacing.section),
            box(24, width: 160),
            const SizedBox(height: Spacing.s12),
            for (var i = 0; i < 3; i++) ...[
              box(56, radius: AppRadius.lg),
              const SizedBox(height: Spacing.s8),
            ],
          ],
        ),
      ),
    );
  }
}

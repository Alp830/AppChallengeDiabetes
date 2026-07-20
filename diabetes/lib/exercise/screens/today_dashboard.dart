import 'package:flutter/material.dart';

import '../../app_features.dart';
import '../../cgm/data/glucose_repository.dart';
import '../../cgm/screens/glucose_context_card.dart';
import '../../sleep/screens/sleep_summary_card.dart';
import '../data/exercise_repository.dart';
import '../data/today_todo_repository.dart';
import '../models/workout_session.dart';
import '../services/workout_insight_service.dart';

const int todayActivityGoalMinutes = 30;

class TodayDashboard extends StatefulWidget {
  const TodayDashboard({
    super.key,
    required this.userId,
    required this.onOpenExercise,
    this.userName,
    this.repository,
    this.now,
    this.todaySessionsStream,
    this.recentSessionsStream,
    this.todoRepository,
    this.todoStateStream,
    this.onSaveTodos,
    this.onLogMeal,
    this.onImportGlucose,
    this.onOpenSleep,
    this.hasGlucoseStream,
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
  });

  final String userId;
  final String? userName;
  final VoidCallback onOpenExercise;
  final ExerciseRepository? repository;
  final DateTime? now;
  final Stream<List<WorkoutSession>>? todaySessionsStream;
  final Stream<List<WorkoutSession>>? recentSessionsStream;
  final TodayTodoRepository? todoRepository;
  final Stream<TodayTodoState>? todoStateStream;
  final Future<void> Function(List<TodayTodo> items)? onSaveTodos;
  final VoidCallback? onLogMeal;
  final VoidCallback? onImportGlucose;
  final VoidCallback? onOpenSleep;

  /// Injectable for tests. When null, the glucose gate falls back to a live
  /// [GlucoseRepository] stream — but only when the glucose slot is enabled.
  final Stream<bool>? hasGlucoseStream;
  final bool diabetesEnabled;

  @override
  State<TodayDashboard> createState() => _TodayDashboardState();
}

class _TodayDashboardState extends State<TodayDashboard> {
  late final DateTime _today;
  late final Stream<List<WorkoutSession>> _todaySessions;
  late final Stream<List<WorkoutSession>> _recentSessions;
  late final Stream<TodayTodoState> _todoState;
  late final Future<void> Function(List<TodayTodo> items) _saveTodos;

  /// Null when the glucose slot is disabled (no meal/import callbacks — e.g. in
  /// tests), so the glucose presence stream is never subscribed off Firestore.
  late final Stream<bool>? _hasGlucose;

  @override
  void initState() {
    super.initState();
    _today = widget.now ?? DateTime.now();
    final glucoseEnabled =
        widget.diabetesEnabled &&
        widget.onLogMeal != null &&
        widget.onImportGlucose != null;
    _hasGlucose = !glucoseEnabled
        ? null
        : widget.hasGlucoseStream ??
              GlucoseRepository().watchHasGlucoseData(widget.userId);
    final needsRepository =
        widget.todaySessionsStream == null ||
        widget.recentSessionsStream == null;
    final repository = needsRepository
        ? widget.repository ?? ExerciseRepository()
        : widget.repository;
    _todaySessions =
        widget.todaySessionsStream ??
        repository!.watchSessionsForDay(widget.userId, _today);
    _recentSessions =
        widget.recentSessionsStream ??
        repository!.watchRecentSessions(widget.userId, limit: 20);
    final todoRepository = widget.todoStateStream == null
        ? widget.todoRepository ?? TodayTodoRepository()
        : widget.todoRepository;
    _todoState =
        widget.todoStateStream ??
        todoRepository!.watchTodos(widget.userId, _today);
    _saveTodos =
        widget.onSaveTodos ??
        (items) => todoRepository!.saveTodos(widget.userId, _today, items);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WorkoutSession>>(
      stream: _recentSessions,
      builder: (context, recentSnapshot) {
        if (recentSnapshot.hasError) {
          return const _DashboardError();
        }
        if (!recentSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return StreamBuilder<List<WorkoutSession>>(
          stream: _todaySessions,
          builder: (context, todaySnapshot) {
            if (todaySnapshot.hasError) {
              return const _DashboardError();
            }
            if (!todaySnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            return StreamBuilder<TodayTodoState>(
              stream: _todoState,
              builder: (context, todoSnapshot) {
                if (todoSnapshot.hasError) {
                  return const _DashboardError();
                }
                if (!todoSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final todoState = todoSnapshot.data!;
                final todos = todoState.isInitialized
                    ? todoState.items
                    : const [
                        TodayTodo(
                          id: 'default-activity',
                          name: 'Complete an activity',
                        ),
                        TodayTodo(
                          id: 'default-30-minutes',
                          name: 'Reach 30 active minutes',
                        ),
                      ];

                _TodayDashboardContent buildContent(bool hasGlucose) {
                  return _TodayDashboardContent(
                    now: _today,
                    userName: widget.userName,
                    todaySessions: todaySnapshot.data!,
                    recentSessions: recentSnapshot.data!,
                    todos: todos,
                    onSaveTodos: _saveTodos,
                    onOpenExercise: widget.onOpenExercise,
                    diabetesEnabled: widget.diabetesEnabled,
                    // The Glucose context card only appears once the user has
                    // imported glucose data (LibreView or demo).
                    glucoseContext:
                        !hasGlucose ||
                            widget.onLogMeal == null ||
                            widget.onImportGlucose == null
                        ? null
                        : GlucoseContextCard(
                            userId: widget.userId,
                            onLogMeal: widget.onLogMeal!,
                            onOpenExercise: widget.onOpenExercise,
                            onImport: widget.onImportGlucose!,
                          ),
                    sleepSummary: widget.onOpenSleep == null
                        ? null
                        : SleepSummaryCard(
                            userId: widget.userId,
                            onOpenSleep: widget.onOpenSleep!,
                            diabetesEnabled: widget.diabetesEnabled,
                          ),
                  );
                }

                final glucoseStream = _hasGlucose;
                if (glucoseStream == null) {
                  return buildContent(false);
                }
                return StreamBuilder<bool>(
                  stream: glucoseStream,
                  builder: (context, glucoseSnapshot) =>
                      buildContent(glucoseSnapshot.data ?? false),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TodayDashboardContent extends StatelessWidget {
  const _TodayDashboardContent({
    required this.now,
    required this.userName,
    required this.todaySessions,
    required this.recentSessions,
    required this.todos,
    required this.onSaveTodos,
    required this.onOpenExercise,
    required this.glucoseContext,
    required this.sleepSummary,
    required this.diabetesEnabled,
  });

  final DateTime now;
  final String? userName;
  final List<WorkoutSession> todaySessions;
  final List<WorkoutSession> recentSessions;
  final List<TodayTodo> todos;
  final Future<void> Function(List<TodayTodo> items) onSaveTodos;
  final VoidCallback onOpenExercise;
  final Widget? glucoseContext;
  final Widget? sleepSummary;
  final bool diabetesEnabled;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = todaySessions.fold<int>(
      0,
      (sum, session) => sum + session.actualDurationSeconds,
    );
    final minutes = (totalSeconds / 60).round();
    final remaining = (todayActivityGoalMinutes - minutes).clamp(
      0,
      todayActivityGoalMinutes,
    );
    final progress = (minutes / todayActivityGoalMinutes).clamp(0.0, 1.0);
    final insights = const WorkoutInsightService().buildInsights(
      recentSessions,
      diabetesEnabled: diabetesEnabled,
    );

    return ListView(
      key: const Key('todayDashboard'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          '${_greeting(now)}${_displayName(userName)}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          _formatFullDate(now),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        _FocusCard(
          minutes: minutes,
          remaining: remaining,
          onOpenExercise: onOpenExercise,
        ),
        const SizedBox(height: 16),
        _ActivityCard(
          sessions: todaySessions,
          minutes: minutes,
          remaining: remaining,
          progress: progress,
          onOpenExercise: onOpenExercise,
        ),
        if (glucoseContext != null) ...[
          const SizedBox(height: 16),
          glucoseContext!,
        ],
        if (sleepSummary != null) ...[
          const SizedBox(height: 16),
          sleepSummary!,
        ],
        const SizedBox(height: 24),
        Text('Up next', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.play_arrow)),
            title: Text(
              remaining > 0
                  ? 'Choose your next activity'
                  : 'Review your exercise progress',
            ),
            subtitle: Text(
              remaining > 0
                  ? 'A short workout can move you toward today’s goal.'
                  : 'Your daily activity goal is complete.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenExercise,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "Today's checklist",
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        _TodoCard(
          key: ValueKey(todos.map((item) => item.id).join('|')),
          initialItems: todos,
          onSave: onSaveTodos,
        ),
        const SizedBox(height: 24),
        Text('Your pattern', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: insights.isEmpty
                ? const Text(
                    'Complete at least three workouts to start seeing patterns in your activity.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        insights.first.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(insights.first.message),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _TodoCard extends StatefulWidget {
  const _TodoCard({
    super.key,
    required this.initialItems,
    required this.onSave,
  });

  final List<TodayTodo> initialItems;
  final Future<void> Function(List<TodayTodo> items) onSave;

  @override
  State<_TodoCard> createState() => _TodoCardState();
}

class _TodoCardState extends State<_TodoCard> {
  late List<TodayTodo> _items = List.of(widget.initialItems);

  @override
  void didUpdateWidget(covariant _TodoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameTodos(oldWidget.initialItems, widget.initialItems)) {
      _items = List.of(widget.initialItems);
    }
  }

  Future<void> _commit(List<TodayTodo> nextItems) async {
    final previous = _items;
    setState(() => _items = nextItems);
    try {
      await widget.onSave(List.unmodifiable(nextItems));
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your checklist. Try again.'),
        ),
      );
    }
  }

  Future<String?> _askForName({String? currentName}) async {
    var enteredName = currentName ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(currentName == null ? 'Add a task' : 'Edit task'),
        content: TextFormField(
          key: const Key('todoNameField'),
          initialValue: currentName,
          autofocus: true,
          maxLength: 100,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Task name',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => enteredName = value,
          onFieldSubmitted: (value) {
            final name = value.trim();
            if (name.isNotEmpty) Navigator.of(context).pop(name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = enteredName.trim();
              if (name.isNotEmpty) Navigator.of(context).pop(name);
            },
            child: Text(currentName == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _add() async {
    final name = await _askForName();
    if (name == null) return;
    final item = TodayTodo(
      id: 'todo-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
    );
    await _commit([..._items, item]);
  }

  Future<void> _edit(TodayTodo item) async {
    final name = await _askForName(currentName: item.name);
    if (name == null || name == item.name) return;
    await _commit([
      for (final current in _items)
        if (current.id == item.id) current.copyWith(name: name) else current,
    ]);
  }

  Future<void> _toggle(TodayTodo item, bool value) async {
    await _commit([
      for (final current in _items)
        if (current.id == item.id)
          current.copyWith(isCompleted: value)
        else
          current,
    ]);
  }

  Future<void> _remove(TodayTodo item) async {
    await _commit(_items.where((current) => current.id != item.id).toList());
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final reordered = List<TodayTodo>.of(_items);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    await _commit(reordered);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('addTodoButton'),
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Add task'),
              ),
            ),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No tasks yet. Add one for today.'),
              )
            else
              ReorderableListView.builder(
                key: const Key('todayTodoList'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _items.length,
                onReorderItem: _reorder,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return ListTile(
                    key: ValueKey(item.id),
                    leading: Checkbox(
                      value: item.isCompleted,
                      onChanged: (value) => _toggle(item, value ?? false),
                    ),
                    title: InkWell(
                      key: ValueKey('edit-${item.id}'),
                      onTap: () => _edit(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          item.name,
                          style: item.isCompleted
                              ? const TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                )
                              : null,
                        ),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: ValueKey('delete-${item.id}'),
                          onPressed: () => _remove(item),
                          tooltip: 'Remove ${item.name}',
                          icon: const Icon(Icons.delete_outline),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: IconButton(
                            onPressed: null,
                            tooltip: 'Move ${item.name}',
                            icon: const Icon(Icons.drag_handle),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

bool _sameTodos(List<TodayTodo> first, List<TodayTodo> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    final a = first[index];
    final b = second[index];
    if (a.id != b.id || a.name != b.name || a.isCompleted != b.isCompleted) {
      return false;
    }
  }
  return true;
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({
    required this.minutes,
    required this.remaining,
    required this.onOpenExercise,
  });

  final int minutes;
  final int remaining;
  final VoidCallback onOpenExercise;

  @override
  Widget build(BuildContext context) {
    final String message;
    final String action;
    if (minutes == 0) {
      message = 'Start with an activity that feels manageable today.';
      action = 'Start an activity';
    } else if (remaining > 0) {
      message = '$remaining minutes remain toward today’s activity goal.';
      action = 'Continue activity';
    } else {
      message = 'You reached today’s 30-minute activity goal.';
      action = 'View exercise';
    }

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Today's focus",
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onOpenExercise,
                icon: const Icon(Icons.directions_run),
                label: Text(action),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.sessions,
    required this.minutes,
    required this.remaining,
    required this.progress,
    required this.onOpenExercise,
  });

  final List<WorkoutSession> sessions;
  final int minutes;
  final int remaining;
  final double progress;
  final VoidCallback onOpenExercise;

  @override
  Widget build(BuildContext context) {
    final displayedSessions = sessions.take(3).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_run),
                const SizedBox(width: 10),
                Text('Activity', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '$minutes of $todayActivityGoalMinutes minutes today',
              key: const Key('todayMinutes'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              remaining == 0
                  ? 'Daily goal complete'
                  : '$remaining minutes remaining',
            ),
            const SizedBox(height: 20),
            Text(
              'Today’s workouts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (displayedSessions.isEmpty)
              const Text('No workouts recorded today yet.')
            else
              for (final session in displayedSessions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.fitness_center),
                  ),
                  title: Text(session.activityName),
                  subtitle: Text(
                    '${(session.actualDurationSeconds / 60).round()} min • ${_formatTime(session.startedAt)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenExercise,
                ),
          ],
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load today’s activity. Check your connection and try again.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _greeting(DateTime date) {
  if (date.hour < 12) return 'Good morning';
  if (date.hour < 18) return 'Good afternoon';
  return 'Good evening';
}

String _displayName(String? name) {
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? '' : ', $trimmed';
}

String _formatFullDate(DateTime date) {
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
  return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
}

String _formatTime(DateTime date) {
  final hour = date.hour == 0
      ? 12
      : (date.hour > 12 ? date.hour - 12 : date.hour);
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
}

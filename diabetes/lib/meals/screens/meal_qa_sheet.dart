import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/spacing.dart';
import '../models/meal_qa_models.dart';
import '../services/meal_qa_service.dart';

/// Opens the "Ask about this meal" sheet, scoped to whatever the user tapped.
///
/// Presentation mirrors the Preferences sheet in `main.dart` so the feature
/// feels native: scroll-controlled, safe-area aware, drag handle, and manual
/// keyboard-inset padding.
Future<void> showMealQaSheet(
  BuildContext context, {
  required MealQaContext meal,
  required MealQuestionScope scope,
  required String apiKey,
  required List<MealQaTurn> history,
  required ValueChanged<List<MealQaTurn>> onHistoryChanged,
  bool showFirstRunTip = false,
  VoidCallback? onTipSeen,
  String? initialQuestion,
  MealQaService? service,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _MealQaSheet(
      meal: meal,
      scope: scope,
      history: history,
      onHistoryChanged: onHistoryChanged,
      showFirstRunTip: showFirstRunTip,
      onTipSeen: onTipSeen,
      initialQuestion: initialQuestion,
      service: service ?? MealQaService(apiKey: apiKey),
    ),
  );
}

class _MealQaSheet extends StatefulWidget {
  const _MealQaSheet({
    required this.meal,
    required this.scope,
    required this.history,
    required this.onHistoryChanged,
    required this.showFirstRunTip,
    required this.onTipSeen,
    required this.initialQuestion,
    required this.service,
  });

  final MealQaContext meal;
  final MealQuestionScope scope;
  final List<MealQaTurn> history;
  final ValueChanged<List<MealQaTurn>> onHistoryChanged;
  final bool showFirstRunTip;
  final VoidCallback? onTipSeen;
  final String? initialQuestion;
  final MealQaService service;

  @override
  State<_MealQaSheet> createState() => _MealQaSheetState();
}

class _MealQaSheetState extends State<_MealQaSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  late List<MealQaTurn> _turns = List.of(widget.history);
  List<String> _chips = const [];
  bool _loadingChips = false;
  bool _thinking = false;
  String? _error;

  /// Kept so the Retry button can resend the question that failed.
  String? _failedQuestion;

  @override
  void initState() {
    super.initState();
    // Everything here is deferred to after the first frame. The sheet is
    // inflated during a build pass, so notifying the host page synchronously
    // (onTipSeen calls setState on AgentPage) would mark an ancestor dirty
    // mid-build and trip the framework assertion.
    final opening = widget.initialQuestion?.trim();
    if (opening != null && opening.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ask(opening);
      });
    } else if (_turns.isEmpty) {
      _loadingChips = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadChips();
      });
    }
    if (widget.showFirstRunTip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onTipSeen?.call();
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadChips() async {
    if (!_loadingChips) setState(() => _loadingChips = true);
    // suggestQuestions never throws; an empty list just hides the row.
    final chips = await widget.service.suggestQuestions(
      widget.meal,
      widget.scope,
    );
    if (!mounted) return;
    setState(() {
      _chips = chips;
      _loadingChips = false;
    });
  }

  Future<void> _ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _thinking) return;

    // History sent to the model is the transcript *before* this question.
    final priorTurns = List.of(_turns);
    setState(() {
      _turns = [..._turns, MealQaTurn.user(trimmed, scope: widget.scope)];
      _chips = const [];
      _thinking = true;
      _error = null;
      _failedQuestion = null;
      _input.clear();
    });
    widget.onHistoryChanged(List.of(_turns));
    _scrollToBottom();

    try {
      final reply = await widget.service.answer(
        meal: widget.meal,
        scope: widget.scope,
        history: priorTurns,
        question: trimmed,
      );
      if (!mounted) return;
      setState(() {
        _turns = [..._turns, MealQaTurn.agent(reply)];
        _thinking = false;
      });
      widget.onHistoryChanged(List.of(_turns));
    } on MealQaException catch (error) {
      if (!mounted) return;
      setState(() {
        // Drop the unanswered user turn so Retry does not duplicate it.
        _turns = _turns.sublist(0, _turns.length - 1);
        _thinking = false;
        debugPrint('meal Q&A: ${error.message}');
        _error = "Couldn't get an answer right now.";
        _failedQuestion = trimmed;
      });
      widget.onHistoryChanged(List.of(_turns));
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.meal.dishName, style: theme.textTheme.titleMedium),
              SizedBox(height: Spacing.s8),
              if (widget.scope.hasQuote) _QuoteBlock(scope: widget.scope),
              if (widget.showFirstRunTip) ...[
                SizedBox(height: Spacing.s8),
                Text(
                  'Tip: tap any ingredient or step to ask about it directly.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              SizedBox(height: Spacing.s12),
              // Bottom-anchored like any chat: a short transcript (or just
              // the chips) sits down by the input instead of floating at the
              // top of an empty column, and longer ones scroll normally.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    key: const Key('mealQaTranscript'),
                    controller: _scroll,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final turn in _turns) _TurnBubble(turn: turn),
                          if (_thinking) const _ThinkingBubble(),
                          if (_error != null)
                            _ErrorBubble(
                              message: _error!,
                              onRetry: _failedQuestion == null
                                  ? null
                                  : () => _ask(_failedQuestion!),
                            ),
                          if (_loadingChips) const _ChipSkeletons(),
                          if (_chips.isNotEmpty)
                            _ChipRow(chips: _chips, onTap: _ask),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: Spacing.s8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('mealQaInput'),
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Ask about ${widget.scope.label}',
                      ),
                      onSubmitted: _ask,
                    ),
                  ),
                  SizedBox(width: Spacing.s8),
                  IconButton.filled(
                    key: const Key('mealQaSend'),
                    tooltip: 'Send question',
                    onPressed: _thinking ? null : () => _ask(_input.text),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
              SizedBox(height: Spacing.s8),
              Text(
                'General food info, not medical advice.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: Spacing.s12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reply-quote style banner showing the exact line the user tapped.
class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.scope});
  final MealQuestionScope scope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 2, color: theme.colorScheme.primary),
          SizedBox(width: Spacing.s8),
          Expanded(
            child: Text(
              scope.quote,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnBubble extends StatelessWidget {
  const _TurnBubble({required this.turn});
  final MealQaTurn turn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: turn.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: Spacing.s8),
        padding: EdgeInsets.symmetric(
          horizontal: Spacing.s12,
          vertical: Spacing.s8,
        ),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: turn.isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          turn.text,
          style: TextStyle(
            color: turn.isUser ? scheme.onPrimaryContainer : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: Spacing.s8, left: Spacing.s4),
        child: Semantics(
          liveRegion: true,
          label: 'Thinking',
          child: const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('mealQaError'),
        margin: EdgeInsets.only(bottom: Spacing.s8),
        padding: EdgeInsets.all(Spacing.s12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "That didn't go through. $message",
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            if (onRetry != null)
              TextButton(
                key: const Key('mealQaRetry'),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.chips, required this.onTap});
  final List<String> chips;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder so a long question wraps inside its chip rather than
    // being clipped at the sheet edge.
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: Spacing.s8,
        runSpacing: Spacing.s8,
        children: [
          for (var index = 0; index < chips.length; index++)
            ActionChip(
              key: Key('mealQaSheetChip_$index'),
              label: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(0, constraints.maxWidth - 48),
                ),
                child: Text(
                  chips[index],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              onPressed: () => onTap(chips[index]),
            ),
        ],
      ),
    );
  }
}

/// Placeholder pills so the chip row does not pop in and shove the transcript.
class _ChipSkeletons extends StatelessWidget {
  const _ChipSkeletons();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: Spacing.s8,
      runSpacing: Spacing.s8,
      children: [
        for (final width in const [180.0, 140.0, 200.0])
          Container(
            width: width,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

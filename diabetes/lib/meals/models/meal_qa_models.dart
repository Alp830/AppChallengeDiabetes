/// Models for the "Ask about this meal" Q&A agent.
///
/// The agent answers questions about a single recommendation the user is
/// already looking at, so the user never has to describe what they are asking
/// about. Everything the agent may see about the user lives in [MealQaContext]
/// — see the privacy note there.
library;

import '../../ai/ai_retry.dart';

/// Which part of the recommendation card the user tapped.
enum MealQuestionScopeKind {
  /// The whole dish (chip row, or the card as a whole).
  meal,

  /// The "why this meal" paragraph.
  reason,

  /// The soft glucose heads-up chip.
  glucoseNote,

  /// One ingredient line.
  ingredient,

  /// One numbered instruction step.
  step,
}

/// What the user tapped, and the exact text to quote back at them.
class MealQuestionScope {
  const MealQuestionScope({required this.kind, this.quote = '', this.ordinal});

  /// Convenience for the whole-dish scope, which has nothing to quote.
  const MealQuestionScope.meal()
    : kind = MealQuestionScopeKind.meal,
      quote = '',
      ordinal = null;

  final MealQuestionScopeKind kind;

  /// Verbatim text of the tapped line. Empty for [MealQuestionScopeKind.meal].
  final String quote;

  /// 1-based position for ingredients and steps; null otherwise.
  final int? ordinal;

  /// Short human label used in the sheet hint and in the prompt,
  /// e.g. `Step 2`, `Ingredient`, `this meal`.
  String get label => switch (kind) {
    MealQuestionScopeKind.meal => 'this meal',
    MealQuestionScopeKind.reason => 'why this meal was picked',
    MealQuestionScopeKind.glucoseNote => 'this blood sugar tip',
    MealQuestionScopeKind.ingredient =>
      ordinal == null ? 'this ingredient' : 'ingredient $ordinal',
    MealQuestionScopeKind.step =>
      ordinal == null ? 'this step' : 'step $ordinal',
  };

  bool get hasQuote => quote.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is MealQuestionScope &&
      other.kind == kind &&
      other.quote == quote &&
      other.ordinal == ordinal;

  @override
  int get hashCode => Object.hash(kind, quote, ordinal);

  @override
  String toString() =>
      'MealQuestionScope(${kind.name}, ordinal: $ordinal, quote: "$quote")';
}

/// One turn in the conversation. Turns are ephemeral — they live in
/// `_AgentPageState` and are dropped when a new recommendation is generated.
class MealQaTurn {
  const MealQaTurn.user(this.text, {this.scope}) : isUser = true;
  const MealQaTurn.agent(this.text) : isUser = false, scope = null;

  final bool isUser;
  final String text;

  /// Set on user turns that were opened by tapping a specific line, so the
  /// transcript still reads correctly after the scope changes.
  final MealQuestionScope? scope;
}

/// Immutable snapshot of everything the Q&A agent is allowed to know.
///
/// PRIVACY: this deliberately carries no `userId`, no CGM readings, and no
/// overnight-sleep data. `glucose_settings_page.dart` promises the user that
/// "Gemini receives meal details, but never glucose readings or your
/// identity" — this class is the single place that promise is enforced.
/// [glucoseNote] is included because it is AI-written advice text already
/// shown on the card, not a reading.
class MealQaContext {
  const MealQaContext({
    required this.dishName,
    required this.reason,
    required this.ingredients,
    required this.instructions,
    this.glucoseNote,
    this.eveningScore,
    this.usedFridgeItems = const [],
    this.estimatedCostPerServing,
  });

  final String dishName;
  final String reason;
  final List<String> ingredients;
  final List<String> instructions;
  final String? glucoseNote;
  final int? eveningScore;
  final List<String> usedFridgeItems;
  final String? estimatedCostPerServing;

  /// The meal block injected into every prompt.
  String toPromptBlock() {
    final buffer = StringBuffer()
      ..writeln('Dish: $dishName')
      ..writeln('Why it was suggested: $reason');
    if (glucoseNote != null && glucoseNote!.trim().isNotEmpty) {
      buffer.writeln('Blood sugar tip already shown to the user: $glucoseNote');
    }
    if (eveningScore != null) {
      buffer.writeln('Evening-fit score (1-5): $eveningScore');
    }
    if (estimatedCostPerServing != null &&
        estimatedCostPerServing!.trim().isNotEmpty) {
      buffer.writeln('Estimated cost: $estimatedCostPerServing');
    }
    if (usedFridgeItems.isNotEmpty) {
      buffer.writeln(
        'Uses these items the user already has: ${usedFridgeItems.join(', ')}',
      );
    }
    buffer.writeln('Ingredients:');
    for (final ingredient in ingredients) {
      buffer.writeln('- $ingredient');
    }
    buffer.writeln('Instructions:');
    for (var index = 0; index < instructions.length; index++) {
      buffer.writeln('${index + 1}. ${instructions[index]}');
    }
    return buffer.toString().trimRight();
  }
}

/// Typed failure so the sheet can show a retryable error instead of crashing
/// on an unchecked cast the way `GeminiMealService` does.
///
/// [retryable] defaults to true because most Q&A failures (a 503, a dropped
/// connection, an empty reply) clear up on the next attempt. The service sets
/// it to false for the ones that never will: a missing key, a 4xx, a block.
class MealQaException implements Exception, RetryableAiError {
  const MealQaException(this.message, {this.statusCode, this.retryable = true});

  final String message;
  @override
  final int? statusCode;
  @override
  final bool retryable;

  @override
  String toString() => message;
}

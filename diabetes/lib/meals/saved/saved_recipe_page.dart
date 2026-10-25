import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_features.dart';
import '../../design/spacing.dart';
import '../../main.dart' show MealRecommendationCard, MealRecommendation;
import '../../settings/data/app_preferences_repository.dart';
import '../models/meal_qa_models.dart';
import '../screens/meal_log_page.dart';
import '../screens/meal_qa_sheet.dart';
import 'saved_recipe.dart';

/// A recipe the user kept, shown in full from local data: opening this page
/// never asks the model for anything.
class SavedRecipePage extends StatefulWidget {
  const SavedRecipePage({
    super.key,
    required this.saved,
    required this.onRemove,
    this.userId,
    this.geminiApiKey = '',
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
    this.preferencesRepository,
  });

  final SavedRecipe saved;

  /// Removes the recipe and closes the page. The list behind it shows the
  /// Undo snackbar, since this page is gone by then.
  final Future<void> Function() onRemove;

  final String? userId;
  final String geminiApiKey;
  final bool diabetesEnabled;
  final AppPreferencesStore? preferencesRepository;

  @override
  State<SavedRecipePage> createState() => _SavedRecipePageState();
}

class _SavedRecipePageState extends State<SavedRecipePage> {
  /// Q&A transcript for this dish, kept here so closing and reopening the
  /// sheet keeps the conversation (same as the Meals tab).
  List<MealQaTurn> _qaHistory = const [];
  bool _qaTipSeen = false;
  StreamSubscription<bool>? _qaTipSubscription;
  bool _removing = false;

  MealRecommendation get _recipe => widget.saved.recipe;

  @override
  void initState() {
    super.initState();
    final userId = widget.userId;
    final repository = widget.preferencesRepository;
    if (userId != null && repository != null) {
      _qaTipSubscription = repository.watchMealQaTipSeen(userId).listen((seen) {
        if (mounted && seen != _qaTipSeen) setState(() => _qaTipSeen = seen);
      });
    }
  }

  @override
  void dispose() {
    _qaTipSubscription?.cancel();
    super.dispose();
  }

  void _markQaTipSeen() {
    if (_qaTipSeen) return;
    setState(() => _qaTipSeen = true);
    final userId = widget.userId;
    final repository = widget.preferencesRepository;
    if (userId == null || repository == null) return;
    // Best effort: a failed write only means the tip shows once more.
    repository.saveMealQaTipSeen(userId).catchError((_) {});
  }

  Future<void> _remove() async {
    if (_removing) return;
    setState(() => _removing = true);
    final navigator = Navigator.of(context);
    try {
      await widget.onRemove();
      if (navigator.canPop()) navigator.pop();
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_recipe.dishName)),
      body: ListView(
        key: const Key('savedRecipeDetail'),
        padding: const EdgeInsets.all(Spacing.margin),
        children: [
          MealRecommendationCard(
            recommendation: _recipe,
            diabetesEnabled: widget.diabetesEnabled,
            difficultyLabel: null,
            isSaved: true,
            budgetFromOriginalRequest: true,
            showBalancingTweak: false,
            onToggleSaved: _removing ? null : _remove,
            onAsk: (scope, {String? initialQuestion}) => showMealQaSheet(
              context,
              meal: MealQaContext(
                dishName: _recipe.dishName,
                reason: _recipe.reason,
                ingredients: _recipe.ingredients,
                instructions: _recipe.instructions,
                glucoseNote: widget.diabetesEnabled
                    ? _recipe.glucoseNote
                    : null,
                eveningScore: _recipe.eveningScore,
                usedFridgeItems: _recipe.usedFridgeItems,
                estimatedCostPerServing: _recipe.estimatedCostPerServing,
              ),
              scope: scope,
              apiKey: widget.geminiApiKey,
              history: _qaHistory,
              onHistoryChanged: (turns) => _qaHistory = turns,
              showFirstRunTip: !_qaTipSeen,
              onTipSeen: _markQaTipSeen,
              initialQuestion: initialQuestion,
            ),
            onLogMeal: widget.userId == null
                ? null
                : () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (context) => MealLogPage(
                        userId: widget.userId!,
                        geminiApiKey: widget.geminiApiKey,
                        initialName: _recipe.dishName,
                        diabetesEnabled: widget.diabetesEnabled,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

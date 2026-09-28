import 'package:flutter/material.dart';

import '../../app_features.dart';
import '../../design/app_radius.dart';
import '../../design/friendly_errors.dart';
import '../../design/load_error.dart';
import '../../design/spacing.dart';
import '../../settings/data/app_preferences_repository.dart';
import 'saved_recipe.dart';
import 'saved_recipe_page.dart';
import 'saved_recipes_repository.dart';

/// The user's kept recipes, newest first. Everything here reads from
/// Firestore only — no AI request is needed to browse or open a recipe.
class SavedRecipesPage extends StatefulWidget {
  const SavedRecipesPage({
    super.key,
    required this.userId,
    required this.store,
    this.geminiApiKey = '',
    this.diabetesEnabled = AppFeatures.diabetesEnabled,
    this.preferencesRepository,
    this.onOpenMeals,
  });

  final String userId;
  final SavedRecipesStore store;
  final String geminiApiKey;
  final bool diabetesEnabled;
  final AppPreferencesStore? preferencesRepository;

  /// Closes this page and lands the user on Meals. Null hides the empty
  /// state's button.
  final VoidCallback? onOpenMeals;

  @override
  State<SavedRecipesPage> createState() => _SavedRecipesPageState();
}

class _SavedRecipesPageState extends State<SavedRecipesPage> {
  late Stream<List<SavedRecipe>> _recipes = widget.store.watchAll(
    widget.userId,
  );

  Future<void> _remove(SavedRecipe saved) async {
    try {
      await widget.store.remove(widget.userId, saved.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Removed from saved recipes'),
            action: SnackBarAction(
              label: 'Undo',
              // Re-saving writes the same fingerprint, so it lands back in
              // the same document.
              onPressed: () => widget.store.save(widget.userId, saved.recipe),
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              FriendlyErrors.describe(error, context: 'saved recipes'),
            ),
            action: SnackBarAction(
              label: 'Try again',
              onPressed: () => _remove(saved),
            ),
          ),
        );
    }
  }

  void _open(SavedRecipe saved) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => SavedRecipePage(
          saved: saved,
          onRemove: () => _remove(saved),
          userId: widget.userId,
          geminiApiKey: widget.geminiApiKey,
          diabetesEnabled: widget.diabetesEnabled,
          preferencesRepository: widget.preferencesRepository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved recipes')),
      body: StreamBuilder<List<SavedRecipe>>(
        stream: _recipes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: LoadErrorView(
                message: "Couldn't load your saved recipes.",
                onRetry: () => setState(
                  () => _recipes = widget.store.watchAll(widget.userId),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const _SavedRecipesSkeleton();
          }
          final recipes = snapshot.data!;
          if (recipes.isEmpty) {
            return _SavedRecipesEmptyState(onOpenMeals: widget.onOpenMeals);
          }

          return ListView.builder(
            key: const Key('savedRecipesList'),
            padding: const EdgeInsets.fromLTRB(
              Spacing.s16,
              Spacing.s12,
              Spacing.s16,
              Spacing.s24,
            ),
            itemCount: recipes.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: Spacing.s8),
              child: _SavedRecipeTile(
                saved: recipes[index],
                index: index,
                onOpen: () => _open(recipes[index]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SavedRecipeTile extends StatelessWidget {
  const _SavedRecipeTile({
    required this.saved,
    required this.index,
    required this.onOpen,
  });

  final SavedRecipe saved;
  final int index;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final savedOn = MaterialLocalizations.of(
      context,
    ).formatShortMonthDay(saved.savedAt);
    return Card(
      child: ListTile(
        key: Key('savedRecipe_$index'),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.s12,
          vertical: Spacing.s8,
        ),
        leading: _Thumbnail(imageUrl: saved.recipe.imageUrl),
        title: Text(saved.recipe.dishName, maxLines: 2),
        subtitle: Text(
          'Saved $savedOn',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Icon(
      Icons.restaurant_menu,
      color: scheme.onPrimaryContainer,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 56,
        width: 56,
        child: ColoredBox(
          color: scheme.primaryContainer,
          child: imageUrl == null
              ? fallback
              : Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  // Same reason as the recipe card: on web an <img> avoids the
                  // localhost-origin 403.
                  webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                  errorBuilder: (context, error, stackTrace) => fallback,
                ),
        ),
      ),
    );
  }
}

class _SavedRecipesEmptyState extends StatelessWidget {
  const _SavedRecipesEmptyState({required this.onOpenMeals});

  final VoidCallback? onOpenMeals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: Spacing.s12),
            Text('No saved recipes yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.s4),
            Text(
              'Save a recipe from Meals and it will show up here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onOpenMeals != null) ...[
              const SizedBox(height: Spacing.s16),
              FilledButton.icon(
                key: const Key('savedRecipesGoToMeals'),
                onPressed: onOpenMeals,
                icon: const Icon(Icons.restaurant_menu),
                label: const Text('Go to Meals'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// List-shaped placeholder shown while the saved recipes load.
class _SavedRecipesSkeleton extends StatelessWidget {
  const _SavedRecipesSkeleton();

  @override
  Widget build(BuildContext context) {
    final block = Theme.of(context).colorScheme.surfaceContainerHigh;
    return Semantics(
      label: 'Loading your saved recipes',
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
            for (var i = 0; i < 4; i++) ...[
              Container(
                height: 80,
                decoration: BoxDecoration(
                  color: block,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
              const SizedBox(height: Spacing.s8),
            ],
          ],
        ),
      ),
    );
  }
}

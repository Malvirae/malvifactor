import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/recipes/data/recipe_repository.dart';
import 'package:malvifactor/features/recipes/presentation/recipe_editor_screen.dart';

class RecipesListScreen extends ConsumerWidget {
  const RecipesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipesAsync = ref.watch(recipesListProvider(''));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recettes partagées'),
        actions: [
          IconButton(
            tooltip: 'Nouvelle recette',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecipeEditorScreen()),
              );
              ref.invalidate(recipesListProvider);
            },
            icon: const Icon(LucideIcons.plus),
          ),
        ],
      ),
      body: recipesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.calories),
        ),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (recipes) {
          if (recipes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.chefHat,
                      size: 42,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 12),
                    const Text('Aucune recette partagée'),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RecipeEditorScreen(),
                          ),
                        );
                        ref.invalidate(recipesListProvider);
                      },
                      icon: const Icon(LucideIcons.plus),
                      label: const Text('Créer une recette'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: recipes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final recipe = recipes[index];
              return Material(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  title: Text(
                    recipe.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${recipe.kcalPer100g.round()} kcal / 100g · P ${recipe.proteinPer100g.round()}g · L ${recipe.fatPer100g.round()}g · G ${recipe.carbsPer100g.round()}g',
                    style: AppTheme.numericStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.pencil, size: 17),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RecipeEditorScreen(
                                existingRecipeId: recipe.id,
                              ),
                            ),
                          );
                          ref.invalidate(recipesListProvider);
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          LucideIcons.trash2,
                          size: 17,
                          color: AppColors.error,
                        ),
                        onPressed: () async {
                          await ref
                              .read(recipeRepositoryProvider)
                              .deleteRecipe(recipe.id);
                          ref.invalidate(recipesListProvider);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

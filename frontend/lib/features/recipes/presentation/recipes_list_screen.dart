import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/food_logger/presentation/widgets/food_search_widgets.dart';
import 'package:malvifactor/features/food_logger/presentation/widgets/recipe_portion_input.dart';
import 'package:malvifactor/features/recipes/data/recipe_repository.dart';
import 'package:malvifactor/features/recipes/presentation/recipe_editor_screen.dart';

class RecipesListScreen extends ConsumerWidget {
  const RecipesListScreen({super.key});

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    String? recipeId,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeEditorScreen(existingRecipeId: recipeId),
      ),
    );
    ref.invalidate(recipesListProvider);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    RecipeSummaryModel recipe,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Supprimer la recette ?'),
        content: Text(
          '« ${recipe.name} » sera définitivement supprimée.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(recipeRepositoryProvider).deleteRecipe(recipe.id);
      ref.invalidate(recipesListProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipesAsync = ref.watch(recipesListProvider(''));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recettes partagées'),
        actions: [
          IconButton(
            tooltip: 'Nouvelle recette',
            onPressed: () => _openEditor(context, ref),
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
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22D3EE).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        LucideIcons.chefHat,
                        size: 32,
                        color: Color(0xFF22D3EE),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Aucune recette partagée',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _openEditor(context, ref),
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
              final sw = recipe.resolvedServingWeightG;
              final hasServings = recipe.hasServings && sw != null;
              const recipeCyan = Color(0xFF22D3EE);
              final portionsCountStr =
                  '${formatFrNumber(recipe.servingsCount, decimals: 1)} ${formatPortionsWord(recipe.servingsCount)}';

              return Material(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openEditor(context, ref, recipeId: recipe.id),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: recipeCyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            LucideIcons.chefHat,
                            size: 20,
                            color: recipeCyan,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      recipe.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const FoodSourceBadge(source: 'recipe'),
                                ],
                              ),
                              if (hasServings) ...[
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceElevated,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: AppColors.border,
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        '$portionsCountStr • ${formatGramsText(sw)}/part',
                                        style: AppTheme.numericStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ColoredMacroInlineRow(
                                  prefix: '1 portion (${formatGramsText(sw)}) : ',
                                  kcal: recipe.perServingKcal,
                                  proteinG: recipe.perServingProteinG,
                                  fatG: recipe.perServingFatG,
                                  carbsG: recipe.perServingCarbsG,
                                  fontSize: 12.5,
                                  macroDecimals: 1,
                                ),
                              ],
                              const SizedBox(height: 4),
                              ColoredMacroInlineRow(
                                prefix: 'Aux 100 g : ',
                                kcal: recipe.kcalPer100g,
                                proteinG: recipe.proteinPer100g,
                                fatG: recipe.fatPer100g,
                                carbsG: recipe.carbsPer100g,
                                suffix:
                                    ' • Total ${formatGramsText(recipe.totalWeightG)}',
                                fontSize: 11.5,
                                macroDecimals: 0,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Modifier',
                              icon: const Icon(
                                LucideIcons.pencil,
                                size: 17,
                                color: AppColors.textSecondary,
                              ),
                              onPressed: () =>
                                  _openEditor(context, ref, recipeId: recipe.id),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Supprimer',
                              icon: const Icon(
                                LucideIcons.trash2,
                                size: 17,
                                color: AppColors.error,
                              ),
                              onPressed: () =>
                                  _confirmDelete(context, ref, recipe),
                            ),
                          ],
                        ),
                      ],
                    ),
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

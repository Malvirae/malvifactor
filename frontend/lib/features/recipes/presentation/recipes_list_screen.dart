import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/core/widgets/food_category_avatar.dart';
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

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var index = 0; index < recipes.length; index++) ...[
                      if (index > 0)
                        const Divider(
                          height: 1,
                          thickness: 0.6,
                          color: Colors.white10,
                        ),
                      Builder(
                        builder: (_) {
                          final recipe = recipes[index];
                          final sw = recipe.resolvedServingWeightG;
                          final hasServings = recipe.hasServings && sw != null;
                          final portionsPill = hasServings
                              ? '${formatFrNumber(recipe.servingsCount, decimals: 1)} port. · ${formatGramsText(sw)}'
                              : null;

                          return InkWell(
                            onTap: () =>
                                _openEditor(context, ref, recipeId: recipe.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  FoodCategoryAvatar(
                                    name: recipe.name,
                                    source: 'recipe',
                                    size: 32,
                                    borderRadius: 9,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                recipe.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.textPrimary,
                                                  height: 1.15,
                                                ),
                                              ),
                                            ),
                                            if (portionsPill != null) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 1.5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF22D3EE)
                                                      .withValues(alpha: 0.14),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color:
                                                        const Color(0xFF22D3EE)
                                                            .withValues(
                                                                alpha: 0.45),
                                                    width: 0.7,
                                                  ),
                                                ),
                                                child: Text(
                                                  portionsPill,
                                                  style: AppTheme.numericStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        const Color(0xFF22D3EE),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (hasServings) ...[
                                          const SizedBox(height: 3),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: ColoredMacroInlineRow(
                                              prefix: '1 port. : ',
                                              kcal: recipe.perServingKcal,
                                              proteinG:
                                                  recipe.perServingProteinG,
                                              fatG: recipe.perServingFatG,
                                              carbsG: recipe.perServingCarbsG,
                                              fontSize: 11.5,
                                              macroDecimals: 1,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 2.5),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: ColoredMacroInlineRow(
                                            prefix: '100g : ',
                                            kcal: recipe.kcalPer100g,
                                            proteinG: recipe.proteinPer100g,
                                            fatG: recipe.fatPer100g,
                                            carbsG: recipe.carbsPer100g,
                                            suffix:
                                                ' · Total ${formatGramsText(recipe.totalWeightG)}',
                                            fontSize: 10.5,
                                            macroDecimals: 0,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 32,
                                      height: 32,
                                    ),
                                    tooltip: 'Modifier',
                                    icon: const Icon(
                                      LucideIcons.pencil,
                                      size: 17,
                                      color: AppColors.textSecondary,
                                    ),
                                    onPressed: () => _openEditor(
                                      context,
                                      ref,
                                      recipeId: recipe.id,
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 32,
                                      height: 32,
                                    ),
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
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/food_logger/presentation/barcode_review_sheet.dart';
import 'package:malvifactor/features/food_logger/presentation/barcode_scanner_screen.dart';
import 'package:malvifactor/features/food_logger/presentation/quantity_bottom_sheet.dart';
import 'package:malvifactor/features/journal/presentation/journal_screen.dart';
import 'package:malvifactor/features/recipes/data/recipe_repository.dart';
import 'package:malvifactor/features/recipes/presentation/recipe_editor_screen.dart';

Future<void> openFoodLoggerSheet(
  BuildContext context, {
  required DateTime targetDate,
  TimeOfDay? initialTime,
  bool openScannerDirectly = false,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => FoodLoggerSheet(
      targetDate: targetDate,
      initialTime: initialTime,
      openScannerDirectly: openScannerDirectly,
    ),
  );
}

class FoodLoggerSheet extends ConsumerStatefulWidget {
  const FoodLoggerSheet({
    super.key,
    required this.targetDate,
    this.initialTime,
    this.openScannerDirectly = false,
  });

  final DateTime targetDate;
  final TimeOfDay? initialTime;
  final bool openScannerDirectly;

  @override
  ConsumerState<FoodLoggerSheet> createState() => _FoodLoggerSheetState();
}

class _FoodLoggerSheetState extends ConsumerState<FoodLoggerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final _quickNameController = TextEditingController();
  final _quickKcalController = TextEditingController();
  final _quickProteinController = TextEditingController(text: '0');
  final _quickFatController = TextEditingController(text: '0');
  final _quickCarbsController = TextEditingController(text: '0');

  Timer? _debounce;
  int _tabIndex = 0; // 0: Aliments, 1: Recettes, 2: Ajout libre
  List<FoodModel> _foods = const [];
  bool _loadingFoods = true;
  bool _submittingQuick = false;

  @override
  void initState() {
    super.initState();
    _searchFoods('');
    if (widget.openScannerDirectly) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openBarcodeScanner());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _quickNameController.dispose();
    _quickKcalController.dispose();
    _quickProteinController.dispose();
    _quickFatController.dispose();
    _quickCarbsController.dispose();
    super.dispose();
  }

  Future<void> _searchFoods(String query) async {
    setState(() => _loadingFoods = true);
    try {
      final list = await ref.read(foodRepositoryProvider).searchFoods(query);
      if (!mounted) return;
      setState(() {
        _foods = list;
        _loadingFoods = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFoods = false);
    }
  }

  Future<void> _openBarcodeScanner() async {
    final food = await Navigator.of(context).push<FoodModel>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (food == null || !mounted) return;

    final reviewed = await showModalBottomSheet<FoodModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => BarcodeReviewSheet(food: food),
    );
    if (reviewed != null && mounted) {
      await _openQuantitySheet(food: reviewed);
    }
  }

  Future<void> _openQuantitySheet({
    FoodModel? food,
    RecipeSummaryModel? recipe,
  }) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => QuantityBottomSheet(
        targetDate: widget.targetDate,
        initialTime: widget.initialTime,
        food: food,
        recipe: recipe,
      ),
    );
    if (added == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openCreateCustomFoodDialog() async {
    final nameCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final kcalCtrl = TextEditingController();
    final pCtrl = TextEditingController(text: '0');
    final fCtrl = TextEditingController(text: '0');
    final cCtrl = TextEditingController(text: '0');

    final created = await showDialog<FoodModel>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Créer un aliment perso (100g)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: brandCtrl,
                decoration:
                    const InputDecoration(labelText: 'Marque (optionnel)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: kcalCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Calories / 100g'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: pCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Prot (g)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: fCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Lip (g)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: cCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Glu (g)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final food =
                  await ref.read(foodRepositoryProvider).createCustomFood(
                        name: nameCtrl.text.trim(),
                        brand: brandCtrl.text.trim(),
                        kcalPer100g: double.tryParse(
                              kcalCtrl.text.replaceAll(',', '.'),
                            ) ??
                            0,
                        proteinPer100g: double.tryParse(
                              pCtrl.text.replaceAll(',', '.'),
                            ) ??
                            0,
                        fatPer100g: double.tryParse(
                              fCtrl.text.replaceAll(',', '.'),
                            ) ??
                            0,
                        carbsPer100g: double.tryParse(
                              cCtrl.text.replaceAll(',', '.'),
                            ) ??
                            0,
                      );
              if (ctx.mounted) Navigator.of(ctx).pop(food);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    if (created != null && mounted) {
      await _openQuantitySheet(food: created);
    }
  }

  Future<void> _submitQuickAdd() async {
    final name = _quickNameController.text.trim();
    final kcal =
        double.tryParse(_quickKcalController.text.replaceAll(',', '.'));
    if (name.isEmpty || kcal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nom et calories requis pour l’ajout rapide.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _submittingQuick = true);
    try {
      await ref.read(foodRepositoryProvider).logQuickAdd(
            loggedDate: widget.targetDate,
            loggedTime: widget.initialTime ?? TimeOfDay.now(),
            customName: name,
            kcal: kcal,
            proteinG: double.tryParse(
                  _quickProteinController.text.replaceAll(',', '.'),
                ) ??
                0,
            fatG: double.tryParse(
                  _quickFatController.text.replaceAll(',', '.'),
                ) ??
                0,
            carbsG: double.tryParse(
                  _quickCarbsController.text.replaceAll(',', '.'),
                ) ??
                0,
          );
      ref.invalidate(dashboardProvider);
      ref.invalidate(journalDayProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submittingQuick = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipesAsync = ref.watch(recipesListProvider(_searchController.text));

    return SafeArea(
      top: true,
      bottom: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.of(context).viewInsets.bottom + 12,
          ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Rechercher un aliment ou une recette...',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                suffixIcon: IconButton(
                  tooltip: 'Scanner un code-barres',
                  onPressed: _openBarcodeScanner,
                  icon: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppColors.calories,
                  ),
                ),
              ),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => _searchFoods(value),
                );
                if (_tabIndex == 1) setState(() {});
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text(
                    'Aliments',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text(
                    'Recettes',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text(
                    'Ajout libre',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {_tabIndex},
              onSelectionChanged: (sel) => setState(() => _tabIndex = sel.first),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: switch (_tabIndex) {
                0 => _buildFoodsTab(),
                1 => _buildRecipesTab(recipesAsync),
                _ => _buildQuickAddTab(),
              },
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildFoodsTab() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _openCreateCustomFoodDialog,
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Créer un aliment perso'),
          ),
        ),
        Expanded(
          child: _loadingFoods
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.calories),
                )
              : _foods.isEmpty
                  ? const Center(
                      child: Text(
                        'Aucun aliment trouvé',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _foods.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final food = _foods[index];
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(
                            food.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '${food.brand != null ? '${food.brand} · ' : ''}${food.kcalPer100g.round()} kcal / 100g · P ${food.proteinPer100g.round()} L ${food.fatPer100g.round()} G ${food.carbsPer100g.round()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.numericStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              food.source.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          onTap: () => _openQuantitySheet(food: food),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildRecipesTab(AsyncValue<List<RecipeSummaryModel>> recipesAsync) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecipeEditorScreen()),
              );
              ref.invalidate(recipesListProvider);
            },
            icon: const Icon(LucideIcons.chefHat, size: 16),
            label: const Text('Nouvelle recette'),
          ),
        ),
        Expanded(
          child: recipesAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.calories),
            ),
            error: (e, _) => Center(child: Text('Erreur : $e')),
            data: (recipes) {
              if (recipes.isEmpty) {
                return const Center(
                  child: Text(
                    'Aucune recette partagée pour le moment.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return ListView.separated(
                itemCount: recipes.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final recipe = recipes[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(
                      recipe.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      '${recipe.kcalPer100g.round()} kcal / 100g · P ${recipe.proteinPer100g.round()} L ${recipe.fatPer100g.round()} G ${recipe.carbsPer100g.round()}',
                      style: AppTheme.numericStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(LucideIcons.pencil, size: 16),
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                RecipeEditorScreen(existingRecipeId: recipe.id),
                          ),
                        );
                        ref.invalidate(recipesListProvider);
                      },
                    ),
                    onTap: () => _openQuantitySheet(recipe: recipe),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAddTab() {
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        TextField(
          controller: _quickNameController,
          decoration: const InputDecoration(
            labelText: 'Nom (ex. Repas restaurant)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _quickKcalController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Calories (kcal)',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _quickProteinController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Protéines (g)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _quickFatController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Lipides (g)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _quickCarbsController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Glucides (g)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _submittingQuick ? null : _submitQuickAdd,
          icon: const Icon(LucideIcons.zap),
          label: const Text('Ajouter au journal'),
        ),
      ],
    );
  }
}

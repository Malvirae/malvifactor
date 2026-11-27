import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/recipes/data/recipe_repository.dart';

class _DraftIngredient {
  _DraftIngredient({required this.food, required this.quantityG});

  final FoodModel food;
  double quantityG;
}

class RecipeEditorScreen extends ConsumerStatefulWidget {
  const RecipeEditorScreen({super.key, this.existingRecipeId});

  final String? existingRecipeId;

  @override
  ConsumerState<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends ConsumerState<RecipeEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _servingsController = TextEditingController(text: '1');
  final _finalWeightController = TextEditingController();

  final List<_DraftIngredient> _ingredients = [];
  bool _isShared = true;
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingRecipeId != null) {
      _loadExisting(widget.existingRecipeId!);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _servingsController.dispose();
    _finalWeightController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting(String id) async {
    setState(() => _isLoading = true);
    try {
      final detail = await ref.read(recipeRepositoryProvider).getRecipe(id);
      if (!mounted) return;
      _nameController.text = detail.name;
      _descController.text = detail.description ?? '';
      _servingsController.text = detail.servingsCount.toStringAsFixed(
        detail.servingsCount % 1 == 0 ? 0 : 1,
      );
      _finalWeightController.text = detail.totalWeightG.toStringAsFixed(0);
      _isShared = detail.isShared;

      _ingredients.clear();
      for (final ing in detail.ingredients) {
        final factor = ing.quantityG > 0 ? 100.0 / ing.quantityG : 0.0;
        _ingredients.add(
          _DraftIngredient(
            food: FoodModel(
              id: ing.foodId,
              source: 'ciqual',
              name: ing.foodName,
              brand: ing.foodBrand,
              servingSizeG: 100,
              kcalPer100g: ing.kcal * factor,
              proteinPer100g: ing.proteinG * factor,
              fatPer100g: ing.fatG * factor,
              carbsPer100g: ing.carbsG * factor,
              fiberPer100g: 0,
            ),
            quantityG: ing.quantityG,
          ),
        );
      }
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible de charger la recette : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _addIngredientModal() async {
    final result = await showModalBottomSheet<_DraftIngredient>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _IngredientPickerSheet(),
    );
    if (result != null) {
      setState(() => _ingredients.add(result));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoutez au moins un ingrédient.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final servings =
        double.tryParse(_servingsController.text.replaceAll(',', '.')) ?? 1.0;
    final finalWeightRaw =
        _finalWeightController.text.trim().replaceAll(',', '.');
    final finalWeight =
        finalWeightRaw.isEmpty ? null : double.tryParse(finalWeightRaw);

    final ingredientsPayload = _ingredients
        .map((e) => {'food_id': e.food.id, 'quantity_g': e.quantityG})
        .toList();

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(recipeRepositoryProvider);
      if (widget.existingRecipeId == null) {
        await repo.createRecipe(
          name: _nameController.text,
          description: _descController.text,
          servingsCount: servings > 0 ? servings : 1.0,
          isShared: _isShared,
          finalWeightG: finalWeight,
          ingredients: ingredientsPayload,
        );
      } else {
        await repo.updateRecipe(
          id: widget.existingRecipeId!,
          name: _nameController.text,
          description: _descController.text,
          servingsCount: servings > 0 ? servings : 1.0,
          isShared: _isShared,
          finalWeightG: finalWeight,
          ingredients: ingredientsPayload,
        );
      }
      ref.invalidate(recipesListProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de l’enregistrement : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawWeight =
        _ingredients.fold<double>(0, (sum, i) => sum + i.quantityG);
    final customFinalWeight = double.tryParse(
      _finalWeightController.text.trim().replaceAll(',', '.'),
    );
    final effectiveWeight =
        (customFinalWeight != null && customFinalWeight > 0)
            ? customFinalWeight
            : rawWeight;

    double totalKcal = 0, totalP = 0, totalF = 0, totalC = 0;
    for (final ing in _ingredients) {
      final factor = ing.quantityG / 100.0;
      totalKcal += ing.food.kcalPer100g * factor;
      totalP += ing.food.proteinPer100g * factor;
      totalF += ing.food.fatPer100g * factor;
      totalC += ing.food.carbsPer100g * factor;
    }
    final scale100 = effectiveWeight > 0 ? 100.0 / effectiveWeight : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingRecipeId == null
              ? 'Nouvelle recette'
              : 'Modifier la recette',
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text(
              'Enregistrer',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.calories),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Container(
                    decoration: AppTheme.gradientCardDecoration(
                      accentColor: AppColors.carbs,
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Valeurs calculées (aux 100g)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              'Total : ${effectiveWeight.round()} g',
                              style: AppTheme.numericStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatPill(
                              label: 'kcal/100g',
                              value: '${(totalKcal * scale100).round()}',
                              color: AppColors.calories,
                            ),
                            _StatPill(
                              label: 'P/100g',
                              value: (totalP * scale100).toStringAsFixed(1),
                              color: AppColors.protein,
                            ),
                            _StatPill(
                              label: 'L/100g',
                              value: (totalF * scale100).toStringAsFixed(1),
                              color: AppColors.fat,
                            ),
                            _StatPill(
                              label: 'G/100g',
                              value: (totalC * scale100).toStringAsFixed(1),
                              color: AppColors.carbs,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Nom de la recette',
                            ),
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? 'Requis' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _descController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Description (optionnel)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _servingsController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Portions',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _finalWeightController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: InputDecoration(
                                    labelText: 'Poids cuit (g)',
                                    hintText: '${rawWeight.round()}',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Partager avec le couple',
                              style: TextStyle(fontSize: 14),
                            ),
                            value: _isShared,
                            activeTrackColor: AppColors.calories,
                            onChanged: (v) => setState(() => _isShared = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ingrédients (${_ingredients.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addIngredientModal,
                        icon: const Icon(LucideIcons.plus, size: 18),
                        label: const Text('Ajouter'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_ingredients.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Aucun ingrédient ajouté. Appuyez sur Ajouter pour rechercher dans Ciqual / Open Food Facts.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._ingredients.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final ing = entry.value;
                      final kcal =
                          ing.food.kcalPer100g * ing.quantityG / 100.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            title: Text(
                              ing.food.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${ing.quantityG.round()} g · ${kcal.round()} kcal',
                              style: AppTheme.numericStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                LucideIcons.trash2,
                                size: 18,
                                color: AppColors.error,
                              ),
                              onPressed: () {
                                setState(() => _ingredients.removeAt(idx));
                              },
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.background,
                            ),
                          )
                        : const Text('Enregistrer la recette'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTheme.numericStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _IngredientPickerSheet extends ConsumerStatefulWidget {
  const _IngredientPickerSheet();

  @override
  ConsumerState<_IngredientPickerSheet> createState() =>
      _IngredientPickerSheetState();
}

class _IngredientPickerSheetState
    extends ConsumerState<_IngredientPickerSheet> {
  final _searchController = TextEditingController();
  final _qtyController = TextEditingController(text: '100');
  Timer? _debounce;
  List<FoodModel> _results = const [];
  bool _loading = true;
  FoodModel? _selectedFood;

  @override
  void initState() {
    super.initState();
    _runSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(foodRepositoryProvider).searchFoods(query);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: _selectedFood == null
            ? Column(
                children: [
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Rechercher un ingrédient (Ciqual / OFF)...',
                      prefixIcon: Icon(LucideIcons.search, size: 18),
                    ),
                    onChanged: (q) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 300),
                        () => _runSearch(q),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.calories,
                            ),
                          )
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final food = _results[index];
                              return ListTile(
                                title: Text(
                                  food.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${food.kcalPer100g.round()} kcal / 100g · P ${food.proteinPer100g.round()}g',
                                  style: AppTheme.numericStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                onTap: () =>
                                    setState(() => _selectedFood = food),
                              );
                            },
                          ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _selectedFood!.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _qtyController,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Quantité (g)',
                      suffixText: 'g',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      final qty = double.tryParse(
                            _qtyController.text.replaceAll(',', '.'),
                          ) ??
                          100.0;
                      if (qty <= 0) return;
                      Navigator.of(context).pop(
                        _DraftIngredient(food: _selectedFood!, quantityG: qty),
                      );
                    },
                    child: const Text('Ajouter l’ingrédient'),
                  ),
                ],
              ),
      ),
    );
  }
}

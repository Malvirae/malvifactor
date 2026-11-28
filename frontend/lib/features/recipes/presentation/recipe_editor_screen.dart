import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/core/widgets/food_category_avatar.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/food_logger/presentation/barcode_review_sheet.dart';
import 'package:malvifactor/features/food_logger/presentation/barcode_scanner_screen.dart';
import 'package:malvifactor/features/food_logger/presentation/widgets/food_search_widgets.dart';
import 'package:malvifactor/features/food_logger/presentation/widgets/recipe_portion_input.dart';
import 'package:malvifactor/features/food_logger/providers/food_basket_provider.dart';
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
      _isShared = detail.isShared;

      _ingredients.clear();
      for (final ing in detail.ingredients) {
        _ingredients.add(
          _DraftIngredient(
            food: FoodModel(
              id: ing.foodId,
              source: ing.source,
              category: ing.category,
              name: ing.foodName,
              brand: ing.resolvedBrand,
              stores: ing.stores,
              servingSizeG: 100,
              kcalPer100g: ing.kcalPer100g,
              proteinPer100g: ing.proteinPer100g,
              fatPer100g: ing.fatPer100g,
              carbsPer100g: ing.carbsPer100g,
              fiberPer100g: 0,
            ),
            quantityG: ing.quantityG,
          ),
        );
      }

      // Leave optional cooked weight empty (Auto mode) whenever stored total_weight_g
      // already matches the sum of ingredients (<= 0.5 g tolerance).
      final ingredientsSum =
          _ingredients.fold<double>(0, (sum, i) => sum + i.quantityG);
      final hasDistinctCookedWeight = detail.totalWeightG > 0 &&
          (detail.totalWeightG - ingredientsSum).abs() > 0.5;
      _finalWeightController.text = hasDistinctCookedWeight
          ? (detail.totalWeightG % 1 == 0
              ? detail.totalWeightG.toStringAsFixed(0)
              : detail.totalWeightG.toStringAsFixed(1))
          : '';
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
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const _IngredientPickerSheet(),
    );
    if (result != null) {
      setState(() => _ingredients.add(result));
    }
  }

  Future<void> _editIngredientQuantityModal(int index) async {
    final current = _ingredients[index];
    final updatedQty = await showModalBottomSheet<double>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _IngredientQuantityEditSheet(ingredient: current),
    );
    if (updatedQty != null && updatedQty > 0 && mounted) {
      setState(() {
        _ingredients[index].quantityG = updatedQty;
      });
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
    final parsedFinalWeight =
        finalWeightRaw.isEmpty ? null : double.tryParse(finalWeightRaw);
    final finalWeight =
        (parsedFinalWeight != null && parsedFinalWeight > 0)
            ? parsedFinalWeight
            : null;

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
    final parsedServings = double.tryParse(
      _servingsController.text.trim().replaceAll(',', '.'),
    );
    final hasValidServings = parsedServings != null && parsedServings > 0;
    final servingWeightG =
        (hasValidServings && effectiveWeight > 0)
            ? effectiveWeight / parsedServings
            : 0.0;
    final scaleServing = hasValidServings ? 1.0 / parsedServings : 0.0;

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
                      accentColor: const Color(0xFF22D3EE),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                hasValidServings && servingWeightG > 0
                                    ? 'Par portion (${formatGramsText(servingWeightG)})'
                                    : 'Par portion',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              hasValidServings
                                  ? '${formatFrNumber(parsedServings, decimals: 1)} ${formatPortionsWord(parsedServings)}'
                                  : '— portions',
                              style: AppTheme.numericStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF22D3EE),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatPill(
                              label: 'kcal / part',
                              value: hasValidServings
                                  ? '${(totalKcal * scaleServing).round()}'
                                  : '—',
                              color: AppColors.calories,
                            ),
                            _StatPill(
                              label: 'P (g)',
                              value: hasValidServings
                                  ? formatFrNumber(
                                      totalP * scaleServing,
                                      decimals: 1,
                                    )
                                  : '—',
                              color: AppColors.protein,
                            ),
                            _StatPill(
                              label: 'L (g)',
                              value: hasValidServings
                                  ? formatFrNumber(
                                      totalF * scaleServing,
                                      decimals: 1,
                                    )
                                  : '—',
                              color: AppColors.fat,
                            ),
                            _StatPill(
                              label: 'G (g)',
                              value: hasValidServings
                                  ? formatFrNumber(
                                      totalC * scaleServing,
                                      decimals: 1,
                                    )
                                  : '—',
                              color: AppColors.carbs,
                            ),
                          ],
                        ),
                        const Divider(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Aux 100 g',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              'Total : ${formatGramsText(effectiveWeight)}',
                              style: AppTheme.numericStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatPill(
                              label: 'kcal/100g',
                              value: '${(totalKcal * scale100).round()}',
                              color: AppColors.calories,
                              compact: true,
                            ),
                            _StatPill(
                              label: 'P/100g',
                              value: formatFrNumber(
                                totalP * scale100,
                                decimals: 1,
                              ),
                              color: AppColors.protein,
                              compact: true,
                            ),
                            _StatPill(
                              label: 'L/100g',
                              value: formatFrNumber(
                                totalF * scale100,
                                decimals: 1,
                              ),
                              color: AppColors.fat,
                              compact: true,
                            ),
                            _StatPill(
                              label: 'G/100g',
                              value: formatFrNumber(
                                totalC * scale100,
                                decimals: 1,
                              ),
                              color: AppColors.carbs,
                              compact: true,
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
                                  onChanged: (_) => setState(() {}),
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
                                    hintText: rawWeight > 0
                                        ? 'Auto : ${formatGramsText(rawWeight)}'
                                        : 'Auto',
                                    suffixIcon: _finalWeightController.text
                                            .trim()
                                            .isNotEmpty
                                        ? Padding(
                                            padding:
                                                const EdgeInsets.only(right: 6),
                                            child: TextButton(
                                              style: TextButton.styleFrom(
                                                minimumSize: const Size(0, 28),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                foregroundColor:
                                                    const Color(0xFF22D3EE),
                                              ),
                                              onPressed: () {
                                                _finalWeightController.clear();
                                                setState(() {});
                                              },
                                              child: const Text(
                                                'Auto',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          )
                                        : null,
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
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var idx = 0;
                              idx < _ingredients.length;
                              idx++) ...[
                            if (idx > 0)
                              const Divider(
                                height: 1,
                                thickness: 0.6,
                                color: Colors.white10,
                              ),
                            _CompactIngredientRow(
                              ingredient: _ingredients[idx],
                              onTapEdit: () =>
                                  _editIngredientQuantityModal(idx),
                              onDelete: () =>
                                  setState(() => _ingredients.removeAt(idx)),
                            ),
                          ],
                        ],
                      ),
                    ),
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
    this.compact = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTheme.numericStyle(
            fontSize: compact ? 14 : 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: compact ? 10.5 : 11,
            color: AppColors.textSecondary,
          ),
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
  final _qtyFocusNode = FocusNode();
  Timer? _localDebounce;
  Timer? _offDebounce;
  int _searchSeq = 0;
  List<GroupedFoodItemModel> _historyItems = const [];
  List<GroupedFoodItemModel> _customItems = const [];
  List<GroupedFoodItemModel> _commonItems = const [];
  List<GroupedFoodItemModel> _offItems = const [];
  final Set<String> _expandedSections = <String>{};
  bool _loadingLocal = false;
  bool _loadingOff = false;
  FoodModel? _selectedFood;

  @override
  void initState() {
    super.initState();
    _qtyFocusNode.addListener(() {
      if (_qtyFocusNode.hasFocus && _qtyController.text.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_qtyFocusNode.hasFocus && _qtyController.text.isNotEmpty) {
            _qtyController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _qtyController.text.length,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _localDebounce?.cancel();
    _offDebounce?.cancel();
    _searchController.dispose();
    _qtyController.dispose();
    _qtyFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    final trimmed = query.trim();
    _localDebounce?.cancel();
    _offDebounce?.cancel();
    _searchSeq += 1;
    final seq = _searchSeq;

    setState(() {
      _expandedSections.clear();
      if (trimmed.length < 2) {
        _historyItems = const [];
        _customItems = const [];
        _commonItems = const [];
        _offItems = const [];
        _loadingLocal = false;
        _loadingOff = false;
      } else {
        _loadingLocal = true;
        _loadingOff = true;
        _offItems = const [];
      }
    });

    if (trimmed.length < 2) return;

    _localDebounce = Timer(const Duration(milliseconds: 150), () {
      _fetchGroupedScope(trimmed, scope: 'local', seq: seq);
    });
    _offDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchGroupedScope(trimmed, scope: 'off', seq: seq);
    });
  }

  Future<void> _fetchGroupedScope(
    String query, {
    required String scope,
    required int seq,
  }) async {
    try {
      final res = await ref.read(foodRepositoryProvider).searchFoodsGrouped(
            query,
            scope: scope,
            limitPerGroup: 25,
          );
      if (!mounted || seq != _searchSeq) return;
      List<GroupedFoodItemModel> onlyFoods(GroupedFoodSectionModel? sec) =>
          (sec?.items ?? const [])
              .where((item) => !item.isRecipe && !item.isQuickAdd)
              .toList();
      setState(() {
        if (scope == 'local') {
          _historyItems = onlyFoods(res.history);
          _customItems = onlyFoods(res.custom);
          _commonItems = onlyFoods(res.common);
          _loadingLocal = false;
        } else {
          _offItems = onlyFoods(res.openfoodfacts);
          _loadingOff = false;
        }
      });
    } catch (_) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        if (scope == 'local') {
          _loadingLocal = false;
        } else {
          _loadingOff = false;
        }
      });
    }
  }

  void _selectFood(FoodModel food) {
    final defaultQty =
        (food.lastQuantityG != null && food.lastQuantityG! > 0)
            ? food.lastQuantityG!
            : 100.0;
    final formatted = defaultQty % 1 == 0
        ? defaultQty.round().toString()
        : defaultQty.toStringAsFixed(1);
    setState(() {
      _selectedFood = food;
      _qtyController.text = formatted;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _qtyFocusNode.requestFocus();
      if (_qtyController.text.isNotEmpty) {
        _qtyController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _qtyController.text.length,
        );
      }
    });
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
      _selectFood(reviewed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetHour = DateTime.now().hour;
    final suggestionsAsync = ref.watch(foodSuggestionsProvider(targetHour));

    return SafeArea(
      top: true,
      bottom: false,
      child: SizedBox(
        height: _selectedFood == null
            ? MediaQuery.of(context).size.height * 0.90
            : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: _selectedFood == null
              ? _buildSearchView(suggestionsAsync)
              : _buildQuantityView(_selectedFood!),
        ),
      ),
    );
  }

  Widget _buildSearchView(
    AsyncValue<FoodSuggestionsResponseModel> suggestionsAsync,
  ) {
    final query = _searchController.text.trim();
    final hasAnyResult = _historyItems.isNotEmpty ||
        _customItems.isNotEmpty ||
        _commonItems.isNotEmpty ||
        _offItems.isNotEmpty;

    void toggleSection(String key) {
      setState(() {
        if (_expandedSections.contains(key)) {
          _expandedSections.remove(key);
        } else {
          _expandedSections.add(key);
        }
      });
    }

    Widget buildIngredientRow(GroupedFoodItemModel item) {
      return FoodSearchResultRow(
        key: ValueKey<String>('ing_${item.id}'),
        name: item.name,
        brand: item.brand,
        stores: item.stores,
        source: item.source,
        category: item.category,
        quantityG: 100.0,
        kcal: item.kcalPer100g,
        proteinG: item.proteinPer100g,
        fatG: item.fatPer100g,
        carbsG: item.carbsPer100g,
        quantityPrefix: '/ ',
        onTapRow: () => _selectFood(item.toFoodModel()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            const Text(
              'Ajouter un ingrédient',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(LucideIcons.x),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Rechercher un ingrédient (Ciqual / OFF)...',
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _openBarcodeScanner,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (query.isNotEmpty) ...[
          Expanded(
            child: query.length < 2
                ? const Center(
                    child: Text(
                      'Tapez au moins 2 caractères pour rechercher...',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : _loadingLocal && !hasAnyResult
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.calories,
                        ),
                      )
                    : !_loadingLocal && !_loadingOff && !hasAnyResult
                        ? const Center(
                            child: Text(
                              'Aucun ingrédient trouvé pour cette recherche.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 12),
                            children: [
                              GroupedSearchSectionWidget<GroupedFoodItemModel>(
                                title: 'Historique',
                                items: _historyItems,
                                expanded: _expandedSections.contains('history'),
                                onToggleExpanded: () =>
                                    toggleSection('history'),
                                itemBuilder: (_, item) =>
                                    buildIngredientRow(item),
                              ),
                              GroupedSearchSectionWidget<GroupedFoodItemModel>(
                                title: 'Perso',
                                items: _customItems,
                                expanded: _expandedSections.contains('custom'),
                                onToggleExpanded: () => toggleSection('custom'),
                                itemBuilder: (_, item) =>
                                    buildIngredientRow(item),
                              ),
                              GroupedSearchSectionWidget<GroupedFoodItemModel>(
                                title: 'Communs (Ciqual)',
                                items: _commonItems,
                                expanded: _expandedSections.contains('common'),
                                onToggleExpanded: () => toggleSection('common'),
                                itemBuilder: (_, item) =>
                                    buildIngredientRow(item),
                              ),
                              GroupedSearchSectionWidget<GroupedFoodItemModel>(
                                title: 'Open Food Facts',
                                items: _offItems,
                                expanded: _expandedSections.contains('off'),
                                onToggleExpanded: () => toggleSection('off'),
                                isLoading: _loadingOff,
                                itemBuilder: (_, item) =>
                                    buildIngredientRow(item),
                              ),
                            ],
                          ),
          ),
        ] else
          Expanded(
            child: suggestionsAsync.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.calories),
              ),
              error: (_, __) => const Center(
                child: Text(
                  'Recherchez un ingrédient ci-dessus ou scannez un code-barres.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              data: (suggestions) {
                final recentIngredients = suggestions.recentFoods
                    .where((item) => !item.isRecipe && !item.isQuickAdd)
                    .toList();
                if (recentIngredients.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Aucun ingrédient récent.\nRecherchez dans Ciqual / OpenFoodFacts ou scannez un produit.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Récents',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: recentIngredients.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final item = recentIngredients[index];
                          return FoodSearchResultRow(
                            name: item.name,
                            brand: item.brand,
                            stores: item.stores,
                            source: item.source,
                            quantityG: 100.0,
                            kcal: item.kcalPer100g,
                            proteinG: item.proteinPer100g,
                            fatG: item.fatPer100g,
                            carbsG: item.carbsPer100g,
                            quantityPrefix: '/ ',
                            onTapRow: () => _selectFood(item.toFoodModel()),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildQuantityView(FoodModel food) {
    final qty =
        double.tryParse(_qtyController.text.trim().replaceAll(',', '.')) ?? 0.0;
    final factor = qty > 0 ? qty / 100.0 : 0.0;
    final previewKcal = food.kcalPer100g * factor;
    final previewP = food.proteinPer100g * factor;
    final previewF = food.fatPer100g * factor;
    final previewC = food.carbsPer100g * factor;

    final metaSubtitle = buildJournalFoodMetaSubtitle(
      name: food.name,
      brand: food.brand,
      stores: food.stores,
      source: food.source,
    );

    void submitAdd() {
      if (qty <= 0) return;
      Navigator.of(context).pop(
        _DraftIngredient(food: food, quantityG: qty),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              icon: const Icon(LucideIcons.arrowLeft, size: 20),
              tooltip: 'Retour aux résultats',
              onPressed: () => setState(() => _selectedFood = null),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          food.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FoodSourceBadge(source: food.source),
                    ],
                  ),
                  if (metaSubtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      metaSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _qtyController,
          focusNode: _qtyFocusNode,
          autofocus: true,
          textInputAction: TextInputAction.done,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTheme.numericStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          decoration: const InputDecoration(
            labelText: 'Quantité (g)',
            suffixText: 'g',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => submitAdd(),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MacroPreviewChip(
                label: 'Calories',
                value: '${previewKcal.round()}',
                unit: 'kcal',
                color: AppColors.calories,
              ),
              _MacroPreviewChip(
                label: 'Protéines',
                value: '${previewP.round()}',
                unit: 'g',
                color: AppColors.protein,
              ),
              _MacroPreviewChip(
                label: 'Lipides',
                value: '${previewF.round()}',
                unit: 'g',
                color: AppColors.fat,
              ),
              _MacroPreviewChip(
                label: 'Glucides',
                value: '${previewC.round()}',
                unit: 'g',
                color: AppColors.carbs,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: qty > 0 ? submitAdd : null,
          child: const Text('Ajouter l’ingrédient'),
        ),
      ],
    );
  }
}

class _CompactIngredientRow extends StatelessWidget {
  const _CompactIngredientRow({
    required this.ingredient,
    required this.onTapEdit,
    required this.onDelete,
  });

  final _DraftIngredient ingredient;
  final VoidCallback onTapEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final food = ingredient.food;
    final factor = ingredient.quantityG / 100.0;
    final metaSubtitle = buildJournalFoodMetaSubtitle(
      name: food.name,
      brand: food.brand,
      stores: food.stores,
      source: food.source,
    );

    return InkWell(
      onTap: onTapEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
        child: Row(
          children: [
            FoodCategoryAvatar(
              name: food.name,
              source: food.source,
              category: food.category,
              size: 32,
              borderRadius: 9,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    food.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.15,
                    ),
                  ),
                  if (metaSubtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      metaSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                        height: 1.15,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ColoredMacroInlineRow(
                      kcal: food.kcalPer100g * factor,
                      proteinG: food.proteinPer100g * factor,
                      fatG: food.fatPer100g * factor,
                      carbsG: food.carbsPer100g * factor,
                      suffix: ' · ${formatGramsText(ingredient.quantityG)}',
                      fontSize: 11.5,
                      macroDecimals: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              tooltip: 'Modifier la quantité',
              onPressed: onTapEdit,
              icon: const Icon(
                Icons.edit_outlined,
                size: 16,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 2),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              tooltip: 'Supprimer',
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline,
                size: 17,
                color: AppColors.error.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IngredientQuantityEditSheet extends StatefulWidget {
  const _IngredientQuantityEditSheet({required this.ingredient});

  final _DraftIngredient ingredient;

  @override
  State<_IngredientQuantityEditSheet> createState() =>
      _IngredientQuantityEditSheetState();
}

class _IngredientQuantityEditSheetState
    extends State<_IngredientQuantityEditSheet> {
  late final TextEditingController _qtyController;
  final FocusNode _qtyFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final initialQty = widget.ingredient.quantityG;
    final formatted = initialQty % 1 == 0
        ? initialQty.round().toString()
        : initialQty.toStringAsFixed(1);
    _qtyController = TextEditingController(text: formatted);

    void selectAll() {
      if (!mounted || _qtyController.text.isEmpty) return;
      _qtyController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _qtyController.text.length,
      );
    }

    _qtyFocusNode.addListener(() {
      if (_qtyFocusNode.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) => selectAll());
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _qtyFocusNode.requestFocus();
      selectAll();
    });
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _qtyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final food = widget.ingredient.food;
    final qty =
        double.tryParse(_qtyController.text.trim().replaceAll(',', '.')) ?? 0.0;
    final factor = qty > 0 ? qty / 100.0 : 0.0;
    final previewKcal = food.kcalPer100g * factor;
    final previewP = food.proteinPer100g * factor;
    final previewF = food.fatPer100g * factor;
    final previewC = food.carbsPer100g * factor;

    final metaSubtitle = buildJournalFoodMetaSubtitle(
      name: food.name,
      brand: food.brand,
      stores: food.stores,
      source: food.source,
    );

    void submit() {
      if (qty <= 0) return;
      Navigator.of(context).pop(qty);
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FoodCategoryAvatar(
                  name: food.name,
                  source: food.source,
                  category: food.category,
                  size: 36,
                  borderRadius: 10,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              food.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FoodSourceBadge(source: food.source),
                        ],
                      ),
                      if (metaSubtitle != null) ...[
                        const SizedBox(height: 2.5),
                        Text(
                          metaSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _qtyController,
              focusNode: _qtyFocusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: AppTheme.numericStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                labelText: 'Quantité (g)',
                suffixText: 'g',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MacroPreviewChip(
                    label: 'Calories',
                    value: '${previewKcal.round()}',
                    unit: 'kcal',
                    color: AppColors.calories,
                  ),
                  _MacroPreviewChip(
                    label: 'Protéines',
                    value: '${previewP.round()}',
                    unit: 'g',
                    color: AppColors.protein,
                  ),
                  _MacroPreviewChip(
                    label: 'Lipides',
                    value: '${previewF.round()}',
                    unit: 'g',
                    color: AppColors.fat,
                  ),
                  _MacroPreviewChip(
                    label: 'Glucides',
                    value: '${previewC.round()}',
                    unit: 'g',
                    color: AppColors.carbs,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: qty > 0 ? submit : null,
              child: const Text('Mettre à jour'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroPreviewChip extends StatelessWidget {
  const _MacroPreviewChip({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        RichText(
          text: TextSpan(
            style: AppTheme.numericStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            children: [
              TextSpan(text: value),
              TextSpan(
                text: ' $unit',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/food_logger/presentation/widgets/food_search_widgets.dart';
import 'package:malvifactor/features/food_logger/presentation/widgets/recipe_portion_input.dart';
import 'package:malvifactor/features/food_logger/providers/food_basket_provider.dart';
import 'package:malvifactor/features/journal/presentation/journal_screen.dart';
import 'package:malvifactor/features/recipes/data/recipe_repository.dart';

enum QuantitySheetOutcome { addedToBasket, loggedSingle }

class QuantityBottomSheet extends ConsumerStatefulWidget {
  const QuantityBottomSheet({
    super.key,
    required this.targetDate,
    this.initialTime,
    this.initialQuantityG,
    this.food,
    this.recipe,
  }) : assert(food != null || recipe != null);

  final DateTime targetDate;
  final TimeOfDay? initialTime;
  final double? initialQuantityG;
  final FoodModel? food;
  final RecipeSummaryModel? recipe;

  @override
  ConsumerState<QuantityBottomSheet> createState() =>
      _QuantityBottomSheetState();
}

class _QuantityBottomSheetState extends ConsumerState<QuantityBottomSheet> {
  late TimeOfDay _selectedTime;
  double _quantityG = 100.0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final initialQty = widget.initialQuantityG ??
        widget.recipe?.resolvedServingWeightG ??
        widget.food?.defaultQuantityG ??
        100.0;
    _quantityG = initialQty > 0 ? initialQty : 100.0;
    _selectedTime = widget.initialTime ?? TimeOfDay.now();
  }

  String get _title => widget.food?.name ?? widget.recipe!.name;
  String? get _subtitle {
    if (widget.food != null) {
      final parts = <String>[
        if (widget.food!.brand != null && widget.food!.brand!.isNotEmpty)
          widget.food!.brand!,
        if (widget.food!.stores != null && widget.food!.stores!.isNotEmpty)
          widget.food!.stores!,
      ];
      return parts.isEmpty ? null : parts.join(' · ');
    }
    final recipe = widget.recipe!;
    if (recipe.hasServings) {
      final portionsStr =
          '${formatFrNumber(recipe.servingsCount, decimals: 1)} ${formatPortionsWord(recipe.servingsCount)}';
      return 'Recette partagée · $portionsStr (${formatGramsText(recipe.totalWeightG)} au total)';
    }
    return 'Recette partagée';
  }

  double get _kcal100 =>
      widget.food?.kcalPer100g ?? widget.recipe!.kcalPer100g;
  double get _protein100 =>
      widget.food?.proteinPer100g ?? widget.recipe!.proteinPer100g;
  double get _fat100 => widget.food?.fatPer100g ?? widget.recipe!.fatPer100g;
  double get _carbs100 =>
      widget.food?.carbsPer100g ?? widget.recipe!.carbsPer100g;

  String get _sourceTag => widget.food?.source ?? 'recipe';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _addToBasket() {
    if (_quantityG <= 0) return;
    final notifier = ref.read(foodBasketProvider.notifier);
    if (_selectedTime.hour != ref.read(foodBasketProvider).targetHour) {
      notifier.setTargetHour(_selectedTime.hour);
    }
    if (widget.food != null) {
      notifier.addFood(widget.food!, quantityG: _quantityG);
    } else if (widget.recipe != null) {
      notifier.addRecipe(widget.recipe!, quantityG: _quantityG);
    }
    Navigator.of(context).pop(QuantitySheetOutcome.addedToBasket);
  }

  Future<void> _submitSingle() async {
    if (_quantityG <= 0) return;
    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(foodRepositoryProvider);
      if (widget.food != null) {
        await repo.logFood(
          loggedDate: widget.targetDate,
          loggedTime: _selectedTime,
          foodId: widget.food!.id,
          quantityG: _quantityG,
        );
      } else {
        await repo.logRecipe(
          loggedDate: widget.targetDate,
          loggedTime: _selectedTime,
          recipeId: widget.recipe!.id,
          quantityG: _quantityG,
        );
      }
      ref.invalidate(dashboardProvider);
      ref.invalidate(journalDayProvider);
      ref.invalidate(fullMetricContextProvider);
      ref.invalidate(foodSuggestionsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(QuantitySheetOutcome.loggedSingle);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de l’ajout : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final factor = _quantityG / 100.0;
    final kcal = _kcal100 * factor;
    final protein = _protein100 * factor;
    final fat = _fat100 * factor;
    final carbs = _carbs100 * factor;
    final timeStr =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FoodSourceBadge(source: _sourceTag),
            ],
          ),
          if (_subtitle != null && _subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _subtitle!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _LiveMacro(
                  label: 'Calories',
                  value: '${kcal.round()}',
                  unit: 'kcal',
                  color: AppColors.calories,
                ),
                _LiveMacro(
                  label: 'Protéines',
                  value: protein.toStringAsFixed(1),
                  unit: 'g',
                  color: AppColors.protein,
                ),
                _LiveMacro(
                  label: 'Lipides',
                  value: fat.toStringAsFixed(1),
                  unit: 'g',
                  color: AppColors.fat,
                ),
                _LiveMacro(
                  label: 'Glucides',
                  value: carbs.toStringAsFixed(1),
                  unit: 'g',
                  color: AppColors.carbs,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PortionAwareQuantitySection(
            initialQuantityG: _quantityG,
            servingWeightG:
                widget.recipe?.resolvedServingWeightG ?? widget.food?.servingWeightG,
            totalWeightG: widget.recipe?.totalWeightG ?? widget.food?.totalWeightG,
            servingsCount: widget.recipe?.servingsCount ?? widget.food?.servings,
            showGramQuickChips: true,
            autofocus: true,
            onQuantityChanged: (grams) => setState(() => _quantityG = grams),
            trailingBesideInput: InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Heure',
                  prefixIcon: Icon(LucideIcons.clock, size: 18),
                ),
                child: Text(
                  timeStr,
                  style: AppTheme.numericStyle(fontSize: 15),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _isSubmitting || _quantityG <= 0 ? null : _submitSingle,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.calories,
                          ),
                        )
                      : const Icon(LucideIcons.zap, size: 16),
                  label: const Text('Logger seul'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed:
                      _isSubmitting || _quantityG <= 0 ? null : _addToBasket,
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: const Text('Ajouter au panier'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveMacro extends StatelessWidget {
  const _LiveMacro({
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
          value,
          style: AppTheme.numericStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          '$label ($unit)',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

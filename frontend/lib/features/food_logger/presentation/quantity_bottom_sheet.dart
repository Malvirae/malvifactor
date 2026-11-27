import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/journal/presentation/journal_screen.dart';
import 'package:malvifactor/features/recipes/data/recipe_repository.dart';

class QuantityBottomSheet extends ConsumerStatefulWidget {
  const QuantityBottomSheet({
    super.key,
    required this.targetDate,
    this.initialTime,
    this.food,
    this.recipe,
  }) : assert(food != null || recipe != null);

  final DateTime targetDate;
  final TimeOfDay? initialTime;
  final FoodModel? food;
  final RecipeSummaryModel? recipe;

  @override
  ConsumerState<QuantityBottomSheet> createState() =>
      _QuantityBottomSheetState();
}

class _QuantityBottomSheetState extends ConsumerState<QuantityBottomSheet> {
  static const List<int> _quickGrams = [30, 50, 100, 150, 200, 250];

  late final TextEditingController _qtyController;
  late TimeOfDay _selectedTime;
  double _quantityG = 100.0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final initialQty = widget.food?.servingSizeG ?? 100.0;
    _quantityG = initialQty > 0 ? initialQty : 100.0;
    _qtyController = TextEditingController(
      text: _quantityG.toStringAsFixed(_quantityG % 1 == 0 ? 0 : 1),
    );
    _selectedTime = widget.initialTime ?? TimeOfDay.now();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  String get _title => widget.food?.name ?? widget.recipe!.name;
  String? get _subtitle => widget.food?.brand ??
      (widget.recipe != null ? 'Recette partagée' : null);
  double get _kcal100 =>
      widget.food?.kcalPer100g ?? widget.recipe!.kcalPer100g;
  double get _protein100 =>
      widget.food?.proteinPer100g ?? widget.recipe!.proteinPer100g;
  double get _fat100 => widget.food?.fatPer100g ?? widget.recipe!.fatPer100g;
  double get _carbs100 =>
      widget.food?.carbsPer100g ?? widget.recipe!.carbsPer100g;

  void _setQuantity(double grams) {
    setState(() {
      _quantityG = grams;
      _qtyController.text = grams.toStringAsFixed(grams % 1 == 0 ? 0 : 1);
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _submit() async {
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
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
          Text(
            _title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
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
          const SizedBox(height: 16),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickGrams.map((g) {
              final selected = (_quantityG - g).abs() < 0.01;
              return ChoiceChip(
                label: Text('${g}g'),
                selected: selected,
                selectedColor: AppColors.calories,
                backgroundColor: AppColors.surfaceElevated,
                labelStyle: AppTheme.numericStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.background
                      : AppColors.textPrimary,
                ),
                side: BorderSide(
                  color: selected ? AppColors.calories : AppColors.border,
                ),
                onSelected: (_) => _setQuantity(g.toDouble()),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _qtyController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: AppTheme.numericStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    labelText: 'Quantité (g)',
                    suffixText: 'g',
                  ),
                  onChanged: (value) {
                    final parsed =
                        double.tryParse(value.replaceAll(',', '.').trim());
                    if (parsed != null && parsed >= 0) {
                      setState(() => _quantityG = parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: InkWell(
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
            ],
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _isSubmitting || _quantityG <= 0 ? null : _submit,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.background,
                    ),
                  )
                : const Icon(LucideIcons.plus),
            label: const Text('Ajouter au journal'),
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

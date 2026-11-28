import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/food_logger/presentation/widgets/food_search_widgets.dart';

class BarcodeReviewSheet extends ConsumerStatefulWidget {
  const BarcodeReviewSheet({
    super.key,
    required this.food,
  });

  final FoodModel food;

  @override
  ConsumerState<BarcodeReviewSheet> createState() => _BarcodeReviewSheetState();
}

class _BarcodeReviewSheetState extends ConsumerState<BarcodeReviewSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _kcalCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _carbsCtrl;
  late final TextEditingController _fiberCtrl;

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final f = widget.food;
    _nameCtrl = TextEditingController(text: f.name);
    _brandCtrl = TextEditingController(text: f.brand ?? '');
    _kcalCtrl = TextEditingController(text: _fmt(f.kcalPer100g));
    _proteinCtrl = TextEditingController(text: _fmt(f.proteinPer100g));
    _fatCtrl = TextEditingController(text: _fmt(f.fatPer100g));
    _carbsCtrl = TextEditingController(text: _fmt(f.carbsPer100g));
    _fiberCtrl = TextEditingController(text: _fmt(f.fiberPer100g));
  }

  String _fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _kcalCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _carbsCtrl.dispose();
    _fiberCtrl.dispose();
    super.dispose();
  }

  double _parse(TextEditingController c, double fallback) {
    return double.tryParse(c.text.trim().replaceAll(',', '.')) ?? fallback;
  }

  Future<void> _saveCorrection() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final f = widget.food;
      final updated = await ref.read(foodRepositoryProvider).customizeFood(
            foodId: f.id,
            name: _nameCtrl.text.trim(),
            brand: _brandCtrl.text.trim(),
            kcalPer100g: _parse(_kcalCtrl, f.kcalPer100g),
            proteinPer100g: _parse(_proteinCtrl, f.proteinPer100g),
            fatPer100g: _parse(_fatCtrl, f.fatPer100g),
            carbsPer100g: _parse(_carbsCtrl, f.carbsPer100g),
            fiberPer100g: _parse(_fiberCtrl, f.fiberPer100g),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Version corrigée enregistrée dans Mes aliments'),
          duration: Duration(milliseconds: 2200),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop<FoodModel>(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la sauvegarde : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.food;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
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
            const SizedBox(height: 14),
            Row(
              children: [
                FoodSourceBadge(source: f.source),
                const SizedBox(width: 8),
                if (f.externalId != null)
                  Text(
                    'EAN ${f.externalId}',
                    style: AppTheme.numericStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _isEditing = !_isEditing),
                  icon: Icon(
                    _isEditing ? LucideIcons.x : LucideIcons.pencil,
                    size: 15,
                  ),
                  label: Text(
                    _isEditing ? 'Annuler' : 'Corriger (100 g)',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!_isEditing) ...[
              Text(
                f.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (f.brand != null && f.brand!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  f.brand!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                decoration: AppTheme.matteCardDecoration(),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Valeurs pour 100 g',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MacroLine(
                      label: 'Calories',
                      value: '${_fmt(f.kcalPer100g)} kcal',
                      color: AppColors.calories,
                    ),
                    const SizedBox(height: 6),
                    _MacroLine(
                      label: 'Protéines',
                      value: '${_fmt(f.proteinPer100g)} g',
                      color: AppColors.protein,
                    ),
                    const SizedBox(height: 6),
                    _MacroLine(
                      label: 'Lipides',
                      value: '${_fmt(f.fatPer100g)} g',
                      color: AppColors.fat,
                    ),
                    const SizedBox(height: 6),
                    _MacroLine(
                      label: 'Glucides',
                      value: '${_fmt(f.carbsPer100g)} g',
                      color: AppColors.carbs,
                    ),
                    const SizedBox(height: 6),
                    _MacroLine(
                      label: 'Fibres',
                      value: '${_fmt(f.fiberPer100g)} g',
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop<FoodModel>(f),
                icon: const Icon(LucideIcons.check),
                label: const Text('Valider et choisir la quantité'),
              ),
            ] else ...[
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom du produit'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _brandCtrl,
                decoration:
                    const InputDecoration(labelText: 'Marque (optionnel)'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _kcalCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Calories / 100g',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _fiberCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Fibres / 100g',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _proteinCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Prot (g)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _fatCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Lip (g)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _carbsCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Glu (g)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveCorrection,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : const Icon(LucideIcons.save),
                label: const Text('Enregistrer la correction'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MacroLine extends StatelessWidget {
  const _MacroLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: AppTheme.numericStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

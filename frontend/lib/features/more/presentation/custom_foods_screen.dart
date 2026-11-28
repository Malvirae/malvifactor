import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/core/widgets/food_category_avatar.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/food_logger/presentation/widgets/food_search_widgets.dart';
import 'package:malvifactor/features/food_logger/presentation/widgets/recipe_portion_input.dart';

class CustomFoodsScreen extends ConsumerStatefulWidget {
  const CustomFoodsScreen({super.key});

  @override
  ConsumerState<CustomFoodsScreen> createState() => _CustomFoodsScreenState();
}

class _CustomFoodsScreenState extends ConsumerState<CustomFoodsScreen> {
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  String _fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

  Future<void> _openFoodEditor({FoodModel? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final brandCtrl = TextEditingController(text: existing?.brand ?? '');
    final servingCtrl = TextEditingController(
      text: _fmt(existing?.servingSizeG ?? 100.0),
    );
    final kcalCtrl = TextEditingController(
      text: existing != null ? _fmt(existing.kcalPer100g) : '',
    );
    final pCtrl = TextEditingController(
      text: existing != null ? _fmt(existing.proteinPer100g) : '0',
    );
    final fCtrl = TextEditingController(
      text: existing != null ? _fmt(existing.fatPer100g) : '0',
    );
    final cCtrl = TextEditingController(
      text: existing != null ? _fmt(existing.carbsPer100g) : '0',
    );
    final fiberCtrl = TextEditingController(
      text: existing != null ? _fmt(existing.fiberPer100g) : '0',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          existing == null
              ? 'Nouvel aliment personnalisé'
              : 'Modifier l’aliment',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: brandCtrl,
                decoration:
                    const InputDecoration(labelText: 'Marque (optionnel)'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: kcalCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Calories / 100g'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: servingCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Portion (g)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: pCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'P (g)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: fCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'L (g)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: cCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'G (g)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fiberCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Fibres / 100g'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              double parse(TextEditingController c, double fallback) =>
                  double.tryParse(c.text.trim().replaceAll(',', '.')) ??
                  fallback;

              final repo = ref.read(foodRepositoryProvider);
              if (existing == null) {
                await repo.createCustomFood(
                  name: nameCtrl.text.trim(),
                  brand: brandCtrl.text.trim(),
                  servingSizeG: parse(servingCtrl, 100.0),
                  kcalPer100g: parse(kcalCtrl, 0.0),
                  proteinPer100g: parse(pCtrl, 0.0),
                  fatPer100g: parse(fCtrl, 0.0),
                  carbsPer100g: parse(cCtrl, 0.0),
                  fiberPer100g: parse(fiberCtrl, 0.0),
                );
              } else {
                await repo.updateCustomFood(
                  foodId: existing.id,
                  name: nameCtrl.text.trim(),
                  brand: brandCtrl.text.trim(),
                  servingSizeG: parse(servingCtrl, existing.servingSizeG),
                  kcalPer100g: parse(kcalCtrl, existing.kcalPer100g),
                  proteinPer100g: parse(pCtrl, existing.proteinPer100g),
                  fatPer100g: parse(fCtrl, existing.fatPer100g),
                  carbsPer100g: parse(cCtrl, existing.carbsPer100g),
                  fiberPer100g: parse(fiberCtrl, existing.fiberPer100g),
                );
              }
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            },
            child: Text(existing == null ? 'Créer' : 'Enregistrer'),
          ),
        ],
      ),
    );

    if (saved == true) {
      ref.invalidate(customFoodsProvider);
    }
  }

  Future<void> _confirmAndDelete(FoodModel food) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Supprimer cet aliment ?'),
        content: Text(
          '« ${food.name} » sera supprimé de vos aliments personnalisés.',
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
    if (confirm != true || !mounted) return;

    try {
      await ref.read(foodRepositoryProvider).deleteCustomFood(food.id);
      ref.invalidate(customFoodsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible de supprimer : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final foodsAsync = ref.watch(customFoodsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aliments personnalisés'),
        actions: [
          IconButton(
            tooltip: 'Ajouter un aliment',
            onPressed: () => _openFoodEditor(),
            icon: const Icon(LucideIcons.plus),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.calories,
        foregroundColor: AppColors.background,
        onPressed: () => _openFoodEditor(),
        child: const Icon(LucideIcons.plus),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _filterController,
              decoration: const InputDecoration(
                hintText: 'Filtrer par nom ou marque...',
                prefixIcon: Icon(LucideIcons.search, size: 18),
              ),
              onChanged: (v) => setState(() => _filterQuery = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: foodsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.calories),
              ),
              error: (e, _) => Center(child: Text('Erreur : $e')),
              data: (foods) {
                final filtered = _filterQuery.isEmpty
                    ? foods
                    : foods
                        .where(
                          (f) =>
                              f.name.toLowerCase().contains(_filterQuery) ||
                              (f.brand ?? '').toLowerCase().contains(_filterQuery),
                        )
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      foods.isEmpty
                          ? 'Aucun aliment personnalisé.'
                          : 'Aucun résultat pour "$_filterQuery".',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
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
                          for (var index = 0;
                              index < filtered.length;
                              index++) ...[
                            if (index > 0)
                              const Divider(
                                height: 1,
                                thickness: 0.6,
                                color: Colors.white10,
                              ),
                            Builder(
                              builder: (_) {
                                final food = filtered[index];
                                final brandStoresMeta =
                                    buildJournalFoodMetaSubtitle(
                                  name: food.name,
                                  brand: food.brand,
                                  stores: food.stores,
                                  source: 'custom',
                                );
                                final ean = (food.externalId ?? '').trim();
                                final hasBarcode = ean.isNotEmpty;
                                final hasMetaRow =
                                    brandStoresMeta != null || hasBarcode;
                                final hasCustomServing = food.servingSizeG > 0 &&
                                    (food.servingSizeG - 100.0).abs() > 0.1;

                                return InkWell(
                                  onTap: () => _openFoodEditor(existing: food),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6.5,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
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
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      food.name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 13.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: AppColors
                                                            .textPrimary,
                                                        height: 1.15,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  const FoodSourceBadge(
                                                    source: 'custom',
                                                  ),
                                                ],
                                              ),
                                              if (hasMetaRow) ...[
                                                const SizedBox(height: 1.5),
                                                Row(
                                                  children: [
                                                    if (brandStoresMeta !=
                                                        null)
                                                      Flexible(
                                                        child: Text(
                                                          brandStoresMeta,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 11,
                                                            color: Color(
                                                                0xFF94A3B8),
                                                            height: 1.15,
                                                          ),
                                                        ),
                                                      ),
                                                    if (brandStoresMeta !=
                                                            null &&
                                                        hasBarcode)
                                                      const Text(
                                                        ' · ',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              Color(0xFF94A3B8),
                                                          height: 1.15,
                                                        ),
                                                      ),
                                                    if (hasBarcode) ...[
                                                      const Icon(
                                                        Icons.qr_code_2_rounded,
                                                        size: 11.5,
                                                        color:
                                                            Color(0xFF94A3B8),
                                                      ),
                                                      const SizedBox(width: 2.5),
                                                      Flexible(
                                                        child: Text(
                                                          ean,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: AppTheme
                                                              .numericStyle(
                                                            fontSize: 10.5,
                                                            color: const Color(
                                                                0xFF94A3B8),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                              const SizedBox(height: 3),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: ColoredMacroInlineRow(
                                                  kcal: food.kcalPer100g,
                                                  proteinG: food.proteinPer100g,
                                                  fatG: food.fatPer100g,
                                                  carbsG: food.carbsPer100g,
                                                  suffix: hasCustomServing
                                                      ? ' / 100g · Port. ${formatGramsText(food.servingSizeG)}'
                                                      : ' / 100g',
                                                  fontSize: 11.5,
                                                  macroDecimals: 1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                            width: 32,
                                            height: 32,
                                          ),
                                          tooltip: 'Éditer',
                                          icon: const Icon(
                                            LucideIcons.pencil,
                                            size: 17,
                                            color: AppColors.textSecondary,
                                          ),
                                          onPressed: () =>
                                              _openFoodEditor(existing: food),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
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
                                              _confirmAndDelete(food),
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
          ),
        ],
      ),
    );
  }
}

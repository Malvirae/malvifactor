import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';

enum FoodSourceFilter {
  all('Tous'),
  ciqual('Ciqual'),
  off('OpenFoodFacts'),
  custom('Perso');

  const FoodSourceFilter(this.label);
  final String label;

  bool matches(String source, {bool includeRecipesInCustom = true}) {
    switch (this) {
      case FoodSourceFilter.all:
        return true;
      case FoodSourceFilter.ciqual:
        return source == 'ciqual';
      case FoodSourceFilter.off:
        return source == 'off' || source == 'openfoodfacts';
      case FoodSourceFilter.custom:
        return source == 'custom' || (includeRecipesInCustom && source == 'recipe');
    }
  }
}

class FoodSearchFilterPills extends StatelessWidget {
  const FoodSearchFilterPills({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final FoodSourceFilter selected;
  final ValueChanged<FoodSourceFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: FoodSourceFilter.values.map((filter) {
          final isSelected = filter == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(filter.label),
              selected: isSelected,
              visualDensity: VisualDensity.compact,
              showCheckmark: false,
              selectedColor: const Color(0xFFF8FAFC),
              backgroundColor: AppColors.surfaceElevated,
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFFF8FAFC)
                    : AppColors.border,
              ),
              labelStyle: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? AppColors.background
                    : AppColors.textSecondary,
              ),
              onSelected: (_) => onSelected(filter),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class FoodSourceBadge extends StatelessWidget {
  const FoodSourceBadge({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color fgColor;
    final String label;
    final IconData? icon;

    switch (source) {
      case 'ciqual':
        bgColor = const Color(0xFF10B981).withValues(alpha: 0.15);
        fgColor = const Color(0xFF34D399);
        label = 'Ciqual';
        icon = Icons.verified_rounded;
      case 'off':
      case 'openfoodfacts':
        bgColor = const Color(0xFFF59E0B).withValues(alpha: 0.15);
        fgColor = const Color(0xFFFBBF24);
        label = 'OFF';
        icon = Icons.qr_code_2_rounded;
      case 'recipe':
        bgColor = const Color(0xFF22D3EE).withValues(alpha: 0.15);
        fgColor = const Color(0xFF22D3EE);
        label = 'Recette';
        icon = null;
      case 'quick_add':
        bgColor = AppColors.calories.withValues(alpha: 0.15);
        fgColor = AppColors.calories;
        label = 'Libre';
        icon = LucideIcons.zap;
      default:
        bgColor = const Color(0xFFA78BFA).withValues(alpha: 0.15);
        fgColor = const Color(0xFFA78BFA);
        label = 'Perso';
        icon = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fgColor.withValues(alpha: 0.55), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fgColor),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: fgColor,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class FoodSearchResultRow extends StatelessWidget {
  const FoodSearchResultRow({
    super.key,
    required this.name,
    required this.brand,
    this.stores,
    required this.source,
    required this.quantityG,
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.onTapRow,
    this.onQuickAdd,
    this.basketCount = 0,
    this.trailingExtra,
    this.quantityPrefix = '• ',
    this.customQuantityText,
  });

  final String name;
  final String? brand;
  final String? stores;
  final String source;
  final double quantityG;
  final double kcal;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final VoidCallback onTapRow;
  final VoidCallback? onQuickAdd;
  final int basketCount;
  final Widget? trailingExtra;
  final String quantityPrefix;
  final String? customQuantityText;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color iconColor;
    switch (source) {
      case 'ciqual':
        icon = LucideIcons.leaf;
        iconColor = const Color(0xFF34D399);
      case 'off':
      case 'openfoodfacts':
        icon = Icons.qr_code_2_rounded;
        iconColor = const Color(0xFFFBBF24);
      case 'recipe':
        icon = LucideIcons.chefHat;
        iconColor = const Color(0xFF22D3EE);
      case 'quick_add':
        icon = LucideIcons.zap;
        iconColor = AppColors.calories;
      default:
        icon = LucideIcons.bookmark;
        iconColor = AppColors.weight;
    }

    final qtyLabel = customQuantityText ??
        (quantityG % 1 == 0
            ? '${quantityG.round()} g'
            : '${quantityG.toStringAsFixed(1)} g');
    final metaParts = <String>[
      name,
      if (brand != null && brand!.isNotEmpty) brand!,
      if (stores != null && stores!.isNotEmpty) stores!,
    ];
    final displayTitle = metaParts.join(' · ');

    return InkWell(
      onTap: onTapRow,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: iconColor),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      FoodSourceBadge(source: source),
                    ],
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: RichText(
                      text: TextSpan(
                        style: AppTheme.numericStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        children: [
                          TextSpan(
                            text: '${kcal.round()} kcal',
                            style: const TextStyle(
                              color: AppColors.calories,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: ' • '),
                          TextSpan(
                            text: '${proteinG.round()}P ',
                            style: const TextStyle(
                              color: AppColors.protein,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: '${fatG.round()}L ',
                            style: const TextStyle(
                              color: AppColors.fat,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: '${carbsG.round()}G',
                            style: const TextStyle(
                              color: AppColors.carbs,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(text: ' $quantityPrefix$qtyLabel'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (trailingExtra != null) trailingExtra!,
            if (onQuickAdd != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: onQuickAdd,
                customBorder: const CircleBorder(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: basketCount > 0
                            ? AppColors.calories.withValues(alpha: 0.18)
                            : AppColors.surfaceElevated,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: basketCount > 0
                              ? AppColors.calories
                              : AppColors.border,
                          width: 1.4,
                        ),
                      ),
                      child: Icon(
                        LucideIcons.plus,
                        size: 17,
                        color: basketCount > 0
                            ? AppColors.calories
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (basketCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: const BoxDecoration(
                            color: AppColors.carbs,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$basketCount',
                            style: AppTheme.numericStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppColors.background,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(width: 6),
              const Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

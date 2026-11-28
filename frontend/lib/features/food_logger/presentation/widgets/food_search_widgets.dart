import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/core/widgets/food_category_avatar.dart';
import 'package:malvifactor/core/widgets/pressable_scale.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: fgColor.withValues(alpha: 0.5), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fgColor),
            const SizedBox(width: 2.5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
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

/// Compact MacroFactor-style food row (~52-56 px height, hairline dividers).
class FoodSearchResultRow extends StatelessWidget {
  const FoodSearchResultRow({
    super.key,
    required this.name,
    required this.brand,
    this.stores,
    required this.source,
    this.category,
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
    this.showSourceBadge = true,
  });

  final String name;
  final String? brand;
  final String? stores;
  final String source;
  final String? category;
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
  final bool showSourceBadge;

  String? _buildInlineMeta() {
    final normName = FoodCategoryResolver.normalize(name);
    final parts = <String>[];
    if (brand != null && brand!.trim().isNotEmpty) {
      final cleanBrand = brand!.trim();
      final normBrand = FoodCategoryResolver.normalize(cleanBrand);
      if (normBrand.isNotEmpty && !normName.contains(normBrand)) {
        parts.add(cleanBrand);
      }
    }
    if (stores != null && stores!.trim().isNotEmpty) {
      final firstStore = stores!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(1)
          .join('');
      if (firstStore.isNotEmpty) {
        final normStore = FoodCategoryResolver.normalize(firstStore);
        final already = parts.any(
          (p) => FoodCategoryResolver.normalize(p) == normStore,
        );
        if (!already && !normName.contains(normStore)) {
          parts.add(firstStore);
        }
      }
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final qtyLabel = customQuantityText ??
        (quantityG % 1 == 0
            ? '${quantityG.round()} g'
            : '${quantityG.toStringAsFixed(1)} g');
    final inlineMeta = _buildInlineMeta();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return InkWell(
      onTap: onTapRow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
        child: Row(
          children: [
            FoodCategoryAvatar(
              name: name,
              source: source,
              category: category,
              size: 32,
              borderRadius: 9,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: name,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  height: 1.15,
                                ),
                              ),
                              if (inlineMeta != null)
                                TextSpan(
                                  text: ' · $inlineMeta',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF94A3B8),
                                    height: 1.15,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showSourceBadge) ...[
                        const SizedBox(width: 6),
                        FoodSourceBadge(source: source),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2.5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: RichText(
                      text: TextSpan(
                        style: AppTheme.numericStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
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
              PressableScale(
                onTap: onQuickAdd,
                scale: 0.92,
                haptic: false,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: basketCount > 0
                            ? AppColors.calories.withValues(alpha: 0.18)
                            : AppColors.surfaceElevated,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: basketCount > 0
                              ? AppColors.calories
                              : AppColors.border,
                          width: 1.3,
                        ),
                      ),
                      child: Icon(
                        LucideIcons.plus,
                        size: 16,
                        color: basketCount > 0
                            ? AppColors.calories
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (basketCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: AnimatedSwitcher(
                          duration: disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: CurvedAnimation(
                              parent: anim,
                              curve: Curves.easeOutBack,
                            ),
                            child: child,
                          ),
                          child: Container(
                            key: ValueKey<int>(basketCount),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.5,
                              vertical: 1,
                            ),
                            decoration: const BoxDecoration(
                              color: AppColors.carbs,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$basketCount',
                              style: AppTheme.numericStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: AppColors.background,
                              ),
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
                size: 17,
                color: AppColors.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hairline separator used between compact food rows.
const Widget kCompactFoodDivider = Divider(
  height: 1,
  thickness: 0.6,
  color: Colors.white10,
);

/// Categorized MacroFactor-style search section: Top 5 by default + "Voir X de plus" toggle.
class GroupedSearchSectionWidget<T> extends StatelessWidget {
  const GroupedSearchSectionWidget({
    super.key,
    required this.title,
    required this.items,
    required this.expanded,
    required this.onToggleExpanded,
    required this.itemBuilder,
    this.isLoading = false,
    this.initialLimit = 5,
  });

  final String title;
  final List<T> items;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final bool isLoading;
  final int initialLimit;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && !isLoading) {
      return const SizedBox.shrink();
    }

    final hasMore = items.length > initialLimit;
    final hiddenCount = items.length - initialLimit;
    final visibleItems =
        expanded || !hasMore ? items : items.take(initialLimit).toList();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (isLoading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: AppColors.calories,
                  ),
                ),
              ],
              const Spacer(),
              if (hasMore)
                InkWell(
                  onTap: onToggleExpanded,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      expanded ? 'Voir moins' : 'Voir $hiddenCount de plus',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.calories,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.calories,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (visibleItems.isNotEmpty)
          AnimatedSize(
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < visibleItems.length; i++) ...[
                  if (i > 0) kCompactFoodDivider,
                  itemBuilder(context, visibleItems[i]),
                ],
              ],
            ),
          )
        else if (isLoading)
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Text(
              'Recherche sur Open Food Facts...',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}

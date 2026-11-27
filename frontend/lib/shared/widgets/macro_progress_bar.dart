import 'package:flutter/material.dart';

import 'package:malvifactor/core/theme/app_theme.dart';

class MacroProgressBar extends StatelessWidget {
  const MacroProgressBar({
    super.key,
    required this.label,
    required this.consumed,
    required this.target,
    required this.unit,
    required this.color,
    this.compact = false,
  });

  final String label;
  final double consumed;
  final double target;
  final String unit;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final safeTarget = target <= 0 ? 1.0 : target;
    final ratio = (consumed / safeTarget).clamp(0.0, 1.0);
    final isOver = consumed > target && target > 0;
    final clampedRemaining = (target - consumed).clamp(0.0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            RichText(
              text: TextSpan(
                style: AppTheme.numericStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  TextSpan(
                    text: consumed.round().toString(),
                    style: TextStyle(
                      color: isOver ? AppColors.error : AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: ' / ${target.round()} $unit',
                    style: AppTheme.numericStyle(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: compact ? 7 : 10,
            backgroundColor: AppColors.surfaceElevated,
            valueColor: AlwaysStoppedAnimation<Color>(
              isOver ? AppColors.error : color,
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 6),
          Text(
            '${clampedRemaining.round()} $unit restants',
            style: AppTheme.numericStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isOver ? AppColors.error : AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

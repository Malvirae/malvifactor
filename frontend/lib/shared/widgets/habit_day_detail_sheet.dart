import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';

String _formatFullFrenchDate(DateTime date) {
  final raw = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(date);
  if (raw.isEmpty) return raw;
  return raw[0].toUpperCase() + raw.substring(1);
}

Future<void> showWeightHabitDetailSheet(
  BuildContext context, {
  required DateTime date,
  required WeightEntryModel entry,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.carbs.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.scale,
                    size: 18,
                    color: AppColors.carbs,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pesée enregistrée',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        _formatFullFrenchDate(date),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              decoration: AppTheme.matteCardDecoration(borderRadius: 14),
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _DetailRow(
                    label: 'Poids relevé',
                    value: '${entry.weightKg.toStringAsFixed(1)} kg',
                    valueColor: AppColors.textPrimary,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(),
                  ),
                  _DetailRow(
                    label: 'Tendance de poids (EWMA)',
                    value: entry.trendWeightKg != null
                        ? '${entry.trendWeightKg!.toStringAsFixed(1)} kg'
                        : 'Non renseigné',
                    valueColor: entry.trendWeightKg != null
                        ? AppColors.weight
                        : AppColors.textMuted,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(),
                  ),
                  _DetailRow(
                    label: 'Masse grasse',
                    value: entry.bodyFatPct != null
                        ? '${entry.bodyFatPct!.toStringAsFixed(1)} %'
                        : 'Non renseigné',
                    valueColor: entry.bodyFatPct != null
                        ? AppColors.weight
                        : AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showFoodHabitDetailSheet(
  BuildContext context, {
  required DateTime date,
  required DaySummaryModel summary,
  MacroSummaryModel? targets,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.calories.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.utensils,
                    size: 18,
                    color: AppColors.calories,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bilan du journal (${summary.entriesCount} entrée${summary.entriesCount > 1 ? 's' : ''})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        _formatFullFrenchDate(date),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _MacroMetricTile(
                    label: 'Calories',
                    value: '${summary.kcal.round()}',
                    target: targets != null && targets.kcal > 0
                        ? '/ ${targets.kcal.round()} kcal'
                        : 'kcal',
                    color: AppColors.calories,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MacroMetricTile(
                    label: 'Protéines',
                    value: '${summary.proteinG.round()}g',
                    target: targets != null && targets.proteinG > 0
                        ? '/ ${targets.proteinG.round()}g'
                        : null,
                    color: AppColors.protein,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MacroMetricTile(
                    label: 'Lipides',
                    value: '${summary.fatG.round()}g',
                    target: targets != null && targets.fatG > 0
                        ? '/ ${targets.fatG.round()}g'
                        : null,
                    color: AppColors.fat,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MacroMetricTile(
                    label: 'Glucides',
                    value: '${summary.carbsG.round()}g',
                    target: targets != null && targets.carbsG > 0
                        ? '/ ${targets.carbsG.round()}g'
                        : null,
                    color: AppColors.carbs,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: AppTheme.numericStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _MacroMetricTile extends StatelessWidget {
  const _MacroMetricTile({
    required this.label,
    required this.value,
    required this.color,
    this.target,
  });

  final String label;
  final String value;
  final String? target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppTheme.numericStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              if (target != null) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    target!,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.numericStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

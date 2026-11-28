import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/core/widgets/pressable_scale.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';

enum AnalyticsRange {
  d7('7J', 7),
  d14('14J', 14),
  m1('1M', 30),
  m3('3M', 90),
  m6('6M', 180),
  y1('1A', 365),
  all('Tout', 0);

  const AnalyticsRange(this.label, this.days);

  final String label;
  final int days;

  int resolveDays(int totalAvailableDays) {
    if (this == AnalyticsRange.all) {
      return math.max(7, totalAvailableDays);
    }
    return days;
  }
}

/// Anchors [points] to the full [range] window ending at the latest point (today),
/// padding leading empty days if history is shorter than the selected window.
List<AnalyticsPointModel> sliceOrPadAnalyticsWindow(
  List<AnalyticsPointModel> points,
  AnalyticsRange range,
) {
  if (points.isEmpty) return const [];
  final windowDays = range.resolveDays(points.length);
  if (points.length >= windowDays) {
    return points.sublist(points.length - windowDays);
  }
  final missing = windowDays - points.length;
  final firstDate = points.first.date;
  final prefix = List<AnalyticsPointModel>.generate(missing, (i) {
    final d = firstDate.subtract(Duration(days: missing - i));
    return AnalyticsPointModel(
      date: d,
      intakeKcal: 0,
      targetKcal: 0,
      weightKg: null,
      trendWeightKg: null,
      estimatedTdeeKcal: 0,
    );
  });
  return [...prefix, ...points];
}

String formatFrDecimal(double value, int decimals) {
  final fixed = value.toStringAsFixed(decimals).replaceAll('.', ',');
  return fixed;
}

String formatFrSignedDecimal(double value, int decimals, String unit) {
  final sign = value > 0 ? '+' : (value < 0 ? '-' : '');
  final absStr = value.abs().toStringAsFixed(decimals).replaceAll('.', ',');
  return '$sign$absStr $unit';
}

String formatFrInt(double value) {
  final rounded = value.round();
  final sign = rounded < 0 ? '-' : '';
  final digits = rounded.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final revIdx = digits.length - i;
    if (i > 0 && revIdx % 3 == 0) {
      buf.write(' ');
    }
    buf.write(digits[i]);
  }
  return '$sign$buf';
}

String formatFrSignedInt(double value, String unit) {
  final rounded = value.round();
  final sign = rounded > 0 ? '+' : '';
  return '$sign${formatFrInt(rounded.toDouble())} $unit';
}

String formatFrDateShort(DateTime date) {
  return DateFormat('d MMM', 'fr_FR').format(date);
}

String formatFrDateRange(DateTime start, DateTime end) {
  final sameYear = start.year == end.year;
  final startStr = sameYear
      ? DateFormat('d MMM', 'fr_FR').format(start)
      : DateFormat('d MMM yyyy', 'fr_FR').format(start);
  final endStr = DateFormat('d MMM yyyy', 'fr_FR').format(end);
  return '$startStr – $endStr';
}

class CleanAxisBounds {
  const CleanAxisBounds({
    required this.minY,
    required this.maxY,
    required this.interval,
  });

  final double minY;
  final double maxY;
  final double interval;
}

CleanAxisBounds computeCleanAxisBounds({
  required double rawMin,
  required double rawMax,
  required List<double> candidateSteps,
  bool clampZero = false,
}) {
  final span = math.max(rawMax - rawMin, candidateSteps.first);
  double step = candidateSteps.last;
  for (final s in candidateSteps) {
    if (span / s <= 5.5) {
      step = s;
      break;
    }
  }
  final pad = step * 0.45;
  var minY = ((rawMin - pad) / step).floor() * step;
  var maxY = ((rawMax + pad) / step).ceil() * step;
  if (clampZero && minY < 0) {
    minY = 0;
  }
  if (maxY <= minY) {
    maxY = minY + step * 2;
  }
  return CleanAxisBounds(minY: minY, maxY: maxY, interval: step);
}

class PeriodPillsBar extends StatelessWidget {
  const PeriodPillsBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AnalyticsRange selected;
  final ValueChanged<AnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: AnalyticsRange.values.map((range) {
          final isSelected = range == selected;
          final disableAnim = MediaQuery.disableAnimationsOf(context);
          return Expanded(
            child: PressableScale(
              onTap: () => onChanged(range),
              scale: 0.96,
              child: AnimatedContainer(
                duration: disableAnim
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFF8FAFC)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  range.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? AppColors.background
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class DynamicScrubHeader extends StatelessWidget {
  const DynamicScrubHeader({
    super.key,
    required this.isScrubbing,
    required this.leftLabel,
    required this.leftValue,
    this.leftSubValue,
    required this.rightLabel,
    required this.rightValue,
    required this.rightColor,
    required this.subtitleText,
  });

  final bool isScrubbing;
  final String leftLabel;
  final String leftValue;
  final String? leftSubValue;
  final String rightLabel;
  final String rightValue;
  final Color rightColor;
  final String subtitleText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    leftLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        leftValue,
                        style: AppTheme.numericStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (leftSubValue != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            leftSubValue!,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.numericStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  rightLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  rightValue,
                  style: AppTheme.numericStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: rightColor,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (isScrubbing) ...[
              const Icon(
                LucideIcons.crosshair,
                size: 13,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              subtitleText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isScrubbing ? FontWeight.w700 : FontWeight.w500,
                color: isScrubbing
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ScaleToggleButton extends StatelessWidget {
  const ScaleToggleButton({
    super.key,
    required this.expanded,
    required this.onTap,
  });

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: expanded
          ? 'Revenir à l’échelle dynamique serrée'
          : 'Échelle étendue (tout l’historique)',
      child: Material(
        color: expanded ? const Color(0xFFF8FAFC) : AppColors.surfaceElevated,
        shape: CircleBorder(
          side: BorderSide(
            color: expanded ? const Color(0xFFF8FAFC) : AppColors.border,
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              Icons.unfold_more_rounded,
              size: 18,
              color: expanded ? AppColors.background : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

enum LegendSwatchKind { band, hollowLine, solidDot, solidBar }

class ChartLegendItemData {
  const ChartLegendItemData({
    required this.label,
    required this.color,
    required this.kind,
  });

  final String label;
  final Color color;
  final LegendSwatchKind kind;
}

class ChartLegendCard extends StatelessWidget {
  const ChartLegendCard({
    super.key,
    required this.items,
  });

  final List<ChartLegendItemData> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.matteCardDecoration(borderRadius: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.spaceEvenly,
        children: items.map((item) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LegendSwatch(item: item),
              const SizedBox(width: 7),
              Text(
                item.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.item});

  final ChartLegendItemData item;

  @override
  Widget build(BuildContext context) {
    switch (item.kind) {
      case LegendSwatchKind.band:
        return Container(
          width: 14,
          height: 10,
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: item.color.withValues(alpha: 0.55),
              width: 1,
            ),
          ),
        );
      case LegendSwatchKind.hollowLine:
        return SizedBox(
          width: 18,
          height: 10,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(height: 2, color: item.color),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: item.color, width: 2),
                ),
              ),
            ],
          ),
        );
      case LegendSwatchKind.solidDot:
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: item.color,
            shape: BoxShape.circle,
          ),
        );
      case LegendSwatchKind.solidBar:
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: item.color,
            borderRadius: BorderRadius.circular(3),
          ),
        );
    }
  }
}

class HorizonRowData {
  const HorizonRowData({
    required this.label,
    required this.sparkValues,
    required this.delta,
    required this.deltaText,
    required this.stableThreshold,
  });

  final String label;
  final List<double> sparkValues;
  final double? delta;
  final String deltaText;
  final double stableThreshold;
}

class HorizonEvolutionCard extends StatelessWidget {
  const HorizonEvolutionCard({
    super.key,
    required this.title,
    required this.accentColor,
    required this.rows,
  });

  final String title;
  final Color accentColor;
  final List<HorizonRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.matteCardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: Divider(),
              ),
            _HorizonEvolutionRow(
              row: rows[i],
              accentColor: accentColor,
            ),
          ],
        ],
      ),
    );
  }
}

class _HorizonEvolutionRow extends StatelessWidget {
  const _HorizonEvolutionRow({
    required this.row,
    required this.accentColor,
  });

  final HorizonRowData row;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final delta = row.delta;
    String trendText = '—';
    Color trendColor = AppColors.textMuted;

    if (delta != null) {
      if (delta.abs() < row.stableThreshold) {
        trendText = '→ Stable';
        trendColor = AppColors.textSecondary;
      } else if (delta < 0) {
        trendText = '↘ Baisse';
        trendColor = accentColor;
      } else {
        trendText = '↗ Hausse';
        trendColor = accentColor;
      }
    }

    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            row.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 22,
            child: CustomPaint(
              painter: _MiniSparklinePainter(
                values: row.sparkValues,
                color: accentColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 76,
          child: Text(
            row.deltaText,
            textAlign: TextAlign.right,
            style: AppTheme.numericStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: delta == null ? AppColors.textMuted : AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 66,
          child: Text(
            trendText,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: trendColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniSparklinePainter extends CustomPainter {
  _MiniSparklinePainter({
    required this.values,
    required this.color,
  });

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      final p = Paint()
        ..color = AppColors.border
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        p,
      );
      return;
    }

    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = maxV - minV;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final norm = span <= 1e-6 ? 0.5 : (values[i] - minV) / span;
      final y = size.height - (norm * (size.height - 4) + 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniSparklinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.values != values;
  }
}

class AnalysisMetricCard extends StatelessWidget {
  const AnalysisMetricCard({
    super.key,
    required this.valueText,
    this.valueColor = AppColors.textPrimary,
    required this.title,
    required this.description,
  });

  final String valueText;
  final Color valueColor;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.matteCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 108, maxWidth: 122),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                valueText,
                textAlign: TextAlign.center,
                style: AppTheme.numericStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

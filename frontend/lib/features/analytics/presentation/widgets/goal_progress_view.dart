import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:malvifactor/core/config/chart_preferences_provider.dart';
import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/presentation/widgets/macro_factor_chart_widgets.dart';
import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';

enum _GoalWeightMode { raw, trend }

class GoalProgressDetailView extends ConsumerStatefulWidget {
  const GoalProgressDetailView({super.key, required this.ctx});

  final FullMetricContext ctx;

  @override
  ConsumerState<GoalProgressDetailView> createState() =>
      _GoalProgressDetailViewState();
}

class _GoalProgressDetailViewState
    extends ConsumerState<GoalProgressDetailView> {
  _GoalWeightMode _mode = _GoalWeightMode.trend;

  double? _pickWeight(AnalyticsPointModel p) {
    if (_mode == _GoalWeightMode.raw) {
      return p.weightKg;
    }
    return p.trendWeightKg ?? p.weightKg;
  }

  @override
  Widget build(BuildContext context) {
    final range = ref
        .watch(chartPreferencesProvider(PersistedChartType.goalProgress))
        .range;
    final points = widget.ctx.points;
    final profile = widget.ctx.profile;
    final isTrend = _mode == _GoalWeightMode.trend;

    // Resolve weight series in selected mode.
    final allRecordedWeights = <MapEntry<DateTime, double>>[];
    for (final p in points) {
      final w = _pickWeight(p);
      if (w != null) {
        allRecordedWeights.add(MapEntry(p.date, w));
      }
    }

    final currentWeight =
        allRecordedWeights.isNotEmpty ? allRecordedWeights.last.value : null;
    final firstHistoryWeight =
        allRecordedWeights.isNotEmpty ? allRecordedWeights.first.value : null;

    // Resolve target weight: explicit profile target, or maintenance baseline / 12-week target.
    final fallbackTarget = profile.goalType == 'maintain'
        ? (firstHistoryWeight ?? currentWeight ?? 70.0)
        : ((currentWeight ?? 70.0) + profile.targetRateKgPerWeek * 12.0);
    final targetWeight = profile.targetWeightKg ?? fallbackTarget;
    final startWeight = firstHistoryWeight ?? currentWeight ?? targetWeight;

    final windowPoints = sliceOrPadAnalyticsWindow(points, range);

    // Build delta bars (daily for <= 30d, weekly buckets for > 30d).
    final bars = _buildProgressBars(
      windowPoints: windowPoints,
      pickWeight: _pickWeight,
      goalType: profile.goalType,
      targetWeight: targetWeight,
      weeklyBuckets: windowPoints.length > 30,
    );

    final deltaValues = [
      for (final b in bars)
        if (b.deltaKg != null) b.deltaKg!,
    ];
    final maxAbsDelta = deltaValues.isEmpty
        ? 0.5
        : deltaValues.map((v) => v.abs()).reduce(math.max);
    final rawMinY =
        deltaValues.isEmpty ? -0.5 : math.min(0.0, deltaValues.reduce(math.min));
    final rawMaxY =
        deltaValues.isEmpty ? 0.5 : math.max(0.0, deltaValues.reduce(math.max));
    final yBounds = computeCleanAxisBounds(
      rawMin: math.min(rawMinY, -maxAbsDelta * 0.1),
      rawMax: math.max(rawMaxY, maxAbsDelta * 0.1),
      candidateSteps: const [0.1, 0.2, 0.5, 1.0, 2.0],
    );

    // Metrics for Analyses & Données
    final diffToTarget =
        currentWeight != null ? currentWeight - targetWeight : null;
    final weeklyRate = _computeModeWeeklyRate(points, _pickWeight);

    // Journal regularity over last 7 days
    final last7Points =
        points.length > 7 ? points.sublist(points.length - 7) : points;
    final logged7Count = last7Points.where((p) => p.intakeKcal > 0).length;
    final regularityPct =
        last7Points.isEmpty ? 0 : ((logged7Count / last7Points.length) * 100).round();

    // Stability (days within ±0.5kg in maintain) or ETA projection (lose/gain)
    String stabilityTitle;
    String stabilityValue;
    String stabilityDesc;
    if (profile.goalType == 'maintain') {
      final inZoneDays = windowPoints.where((p) {
        final w = _pickWeight(p);
        return w != null && (w - targetWeight).abs() <= 0.5;
      }).length;
      final totalWeighed =
          windowPoints.where((p) => _pickWeight(p) != null).length;
      stabilityTitle = 'Stabilité dans la cible';
      stabilityValue = totalWeighed > 0 ? '$inZoneDays / $totalWeighed j' : '-- j';
      stabilityDesc =
          'Nombre de jours pesés dans la zone de maintien (±0,5 kg autour de ${formatFrDecimal(targetWeight, 1)} kg) sur la période.';
    } else {
      stabilityTitle = 'Projection d’atteinte';
      if (currentWeight != null &&
          weeklyRate != null &&
          ((profile.goalType == 'lose' && weeklyRate < -0.02) ||
              (profile.goalType == 'gain' && weeklyRate > 0.02))) {
        final remainingKg = targetWeight - currentWeight;
        final weeksLeft = (remainingKg / weeklyRate).abs();
        final daysLeft = (weeksLeft * 7).round().clamp(1, 3650);
        final eta = DateTime.now().add(Duration(days: daysLeft));
        stabilityValue = DateFormat('d MMM yyyy', 'fr_FR').format(eta);
        stabilityDesc =
            'Date estimée pour atteindre ${formatFrDecimal(targetWeight, 1)} kg au rythme actuel.';
      } else {
        stabilityValue = 'En attente';
        stabilityDesc =
            'Poursuivez le suivi régulier pour estimer la date d’atteinte de ${formatFrDecimal(targetWeight, 1)} kg.';
      }
    }

    // Percentage accomplished for lose/gain
    double? pctAccomplished;
    if (profile.goalType != 'maintain' && currentWeight != null) {
      final totalSpan = (targetWeight - startWeight).abs();
      if (totalSpan > 0.1) {
        final progressed = profile.goalType == 'lose'
            ? (startWeight - currentWeight)
            : (currentWeight - startWeight);
        pctAccomplished = ((progressed / totalSpan) * 100.0).clamp(0.0, 100.0);
      }
    }

    final gapLabel = diffToTarget == null
        ? '-- kg'
        : (profile.goalType == 'maintain'
            ? formatFrSignedDecimal(diffToTarget, 1, 'kg')
            : '${formatFrDecimal(diffToTarget.abs(), 1)} kg restants');

    final gaugeCaption = profile.goalType == 'maintain'
        ? (isTrend
            ? 'Le maintien actif est basé sur votre tendance de poids.'
            : 'Le maintien actif est basé sur votre poids brut.')
        : (pctAccomplished != null
            ? 'Progression de ${pctAccomplished.round()} % vers votre objectif de ${formatFrDecimal(targetWeight, 1)} kg.'
            : 'Suivi basé sur votre ${isTrend ? 'tendance de poids' : 'poids brut'}.');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        // Top toggle: Poids brut | Tendance de poids
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: _ModeTabButton(
                  label: 'Poids brut',
                  selected: _mode == _GoalWeightMode.raw,
                  onTap: () => setState(() => _mode = _GoalWeightMode.raw),
                ),
              ),
              Expanded(
                child: _ModeTabButton(
                  label: 'Tendance de poids',
                  selected: _mode == _GoalWeightMode.trend,
                  onTap: () => setState(() => _mode = _GoalWeightMode.trend),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PeriodPillsBar(
          selected: range,
          onChanged: (r) => ref
              .read(chartPreferencesProvider(PersistedChartType.goalProgress)
                  .notifier)
              .setRange(r),
        ),
        const SizedBox(height: 12),

        // Top Bar Chart with dynamic Y-scale
        Container(
          decoration: AppTheme.matteCardDecoration(),
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    windowPoints.length > 30
                        ? 'Variation hebdomadaire (kg)'
                        : 'Variation par pesée (kg)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    formatFrDateRange(
                      windowPoints.isNotEmpty
                          ? windowPoints.first.date
                          : DateTime.now(),
                      windowPoints.isNotEmpty
                          ? windowPoints.last.date
                          : DateTime.now(),
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (deltaValues.isEmpty)
                const SizedBox(
                  height: 170,
                  child: Center(
                    child: Text(
                      'Pas encore assez de pesées sur cette période',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 185,
                  child: BarChart(
                    BarChartData(
                      minY: yBounds.minY,
                      maxY: yBounds.maxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: yBounds.interval,
                        getDrawingHorizontalLine: (val) => FlLine(
                          color: val.abs() < 1e-6
                              ? AppColors.textMuted
                              : AppColors.border,
                          strokeWidth: val.abs() < 1e-6 ? 1.2 : 1,
                          dashArray: val.abs() < 1e-6 ? null : [4, 4],
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            interval: yBounds.interval,
                            getTitlesWidget: (val, _) => Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                formatFrSignedDecimal(val, 1, ''),
                                style: AppTheme.numericStyle(
                                  fontSize: 10,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (val, meta) {
                              final idx = val.toInt();
                              if (idx < 0 || idx >= bars.length) {
                                return const SizedBox.shrink();
                              }
                              final step = math.max(1, (bars.length / 4).floor());
                              if (idx % step != 0 && idx != bars.length - 1) {
                                return const SizedBox.shrink();
                              }
                              if (idx != bars.length - 1 &&
                                  (bars.length - 1 - idx) < step * 0.6) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  formatFrDateShort(bars[idx].date),
                                  style: AppTheme.numericStyle(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => AppColors.surfaceElevated,
                          getTooltipItem: (group, _, rod, __) {
                            final idx = group.x;
                            final d = idx >= 0 && idx < bars.length
                                ? formatFrDateShort(bars[idx].date)
                                : '';
                            return BarTooltipItem(
                              '$d : ${formatFrSignedDecimal(rod.toY, 2, 'kg')}',
                              AppTheme.numericStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary,
                              ),
                            );
                          },
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < bars.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: bars[i].deltaKg == null
                                ? const []
                                : [
                                    BarChartRodData(
                                      fromY: 0,
                                      toY: bars[i].deltaKg!,
                                      color: bars[i].isToward
                                          ? AppColors.goalToward
                                          : AppColors.goalAway,
                                      width: bars.length > 22
                                          ? 4
                                          : (bars.length > 10 ? 8 : 13),
                                      borderRadius: BorderRadius.vertical(
                                        top: bars[i].deltaKg! >= 0
                                            ? const Radius.circular(3)
                                            : Radius.zero,
                                        bottom: bars[i].deltaKg! < 0
                                            ? const Radius.circular(3)
                                            : Radius.zero,
                                      ),
                                    ),
                                  ],
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const ChartLegendCard(
                items: [
                  ChartLegendItemData(
                    label: 'Vers l’objectif',
                    color: AppColors.goalToward,
                    kind: LegendSwatchKind.solidBar,
                  ),
                  ChartLegendItemData(
                    label: 'Éloignement',
                    color: AppColors.goalAway,
                    kind: LegendSwatchKind.solidBar,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Semi-circular Gauge Card
        Container(
          decoration: AppTheme.matteCardDecoration(),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    currentWeight != null
                        ? '${formatFrDecimal(currentWeight, 1)} kg'
                        : '-- kg',
                    style: AppTheme.numericStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.weight.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      pctAccomplished != null
                          ? '${pctAccomplished.round()} % accompli'
                          : 'Cible : ${formatFrDecimal(targetWeight, 1)} kg',
                      style: AppTheme.numericStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.weight,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 165,
                width: double.infinity,
                child: CustomPaint(
                  painter: _GoalProgressGaugePainter(
                    currentWeight: currentWeight ?? targetWeight,
                    targetWeight: targetWeight,
                    startWeight: startWeight,
                    goalType: profile.goalType,
                    targetLabel: '${formatFrDecimal(targetWeight, 1)} kg',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sous l’objectif',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Text(
                    'Zone cible',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.weight,
                    ),
                  ),
                  Text(
                    'Au-dessus',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                gaugeCaption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Analyses & Données',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        AnalysisMetricCard(
          valueText: gapLabel,
          valueColor: AppColors.weight,
          title: 'Écart à l’objectif',
          description:
              'Différence entre votre ${isTrend ? 'tendance de poids actuelle' : 'poids brut actuel'} et votre objectif (${formatFrDecimal(targetWeight, 1)} kg).',
        ),
        const SizedBox(height: 10),
        AnalysisMetricCard(
          valueText: weeklyRate != null
              ? '${formatFrSignedDecimal(weeklyRate, 2, 'kg')}/sem.'
              : '-- kg/sem.',
          title: 'Rythme réel vs Cible',
          description:
              'Vitesse hebdomadaire actuelle comparée à l’objectif du programme (${formatFrSignedDecimal(profile.targetRateKgPerWeek, 2, 'kg')} / sem.).',
        ),
        const SizedBox(height: 10),
        AnalysisMetricCard(
          valueText: stabilityValue,
          title: stabilityTitle,
          description: stabilityDesc,
        ),
        const SizedBox(height: 10),
        AnalysisMetricCard(
          valueText: '$regularityPct %',
          valueColor: AppColors.calories,
          title: 'Régularité du journal (7j)',
          description:
              'Pourcentage de journées renseignées cette semaine ($logged7Count / ${last7Points.length} jours).',
        ),
      ],
    );
  }
}

class _ModeTabButton extends StatelessWidget {
  const _ModeTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected ? Border.all(color: AppColors.border) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ProgressBarEntry {
  const _ProgressBarEntry({
    required this.date,
    required this.deltaKg,
    required this.isToward,
  });

  final DateTime date;
  final double? deltaKg;
  final bool isToward;
}

List<_ProgressBarEntry> _buildProgressBars({
  required List<AnalyticsPointModel> windowPoints,
  required double? Function(AnalyticsPointModel) pickWeight,
  required String goalType,
  required double targetWeight,
  required bool weeklyBuckets,
}) {
  final buckets = <MapEntry<DateTime, double?>>[];
  if (!weeklyBuckets) {
    for (final p in windowPoints) {
      buckets.add(MapEntry(p.date, pickWeight(p)));
    }
  } else {
    for (var i = 0; i < windowPoints.length; i += 7) {
      final end = math.min(i + 7, windowPoints.length);
      final slice = windowPoints.sublist(i, end);
      final weights = [
        for (final p in slice)
          if (pickWeight(p) != null) pickWeight(p)!,
      ];
      final avg = weights.isEmpty
          ? null
          : weights.reduce((a, b) => a + b) / weights.length;
      buckets.add(MapEntry(slice.last.date, avg));
    }
  }

  final bars = <_ProgressBarEntry>[];
  double? prevValue;
  for (var i = 0; i < buckets.length; i++) {
    final date = buckets[i].key;
    final curr = buckets[i].value;
    if (curr == null) {
      bars.add(_ProgressBarEntry(date: date, deltaKg: null, isToward: true));
      continue;
    }
    if (prevValue == null) {
      prevValue = curr;
      bars.add(_ProgressBarEntry(date: date, deltaKg: null, isToward: true));
      continue;
    }
    final delta = curr - prevValue;
    bool isToward;
    if (goalType == 'lose') {
      isToward = delta <= 0;
    } else if (goalType == 'gain') {
      isToward = delta >= 0;
    } else {
      isToward =
          (curr - targetWeight).abs() <= (prevValue - targetWeight).abs() + 0.02;
    }
    bars.add(
      _ProgressBarEntry(
        date: date,
        deltaKg: delta,
        isToward: isToward,
      ),
    );
    prevValue = curr;
  }
  return bars;
}

double? _computeModeWeeklyRate(
  List<AnalyticsPointModel> points,
  double? Function(AnalyticsPointModel) pickWeight,
) {
  final start = math.max(0, points.length - 21);
  final valid = <MapEntry<int, double>>[];
  for (var i = start; i < points.length; i++) {
    final w = pickWeight(points[i]);
    if (w != null) {
      valid.add(MapEntry(i - start, w));
    }
  }
  if (valid.length < 2) return null;

  double sumW = 0;
  double sumWX = 0;
  double sumWY = 0;
  double sumWXX = 0;
  double sumWXY = 0;

  for (final e in valid) {
    final x = e.key.toDouble();
    final y = e.value;
    final w = 1.0 + (x / 21.0) * 2.0;
    sumW += w;
    sumWX += w * x;
    sumWY += w * y;
    sumWXX += w * x * x;
    sumWXY += w * x * y;
  }

  final denom = sumW * sumWXX - sumWX * sumWX;
  if (denom.abs() < 1e-6) return 0.0;
  return ((sumW * sumWXY - sumWX * sumWY) / denom) * 7.0;
}

class _GoalProgressGaugePainter extends CustomPainter {
  _GoalProgressGaugePainter({
    required this.currentWeight,
    required this.targetWeight,
    required this.startWeight,
    required this.goalType,
    required this.targetLabel,
  });

  final double currentWeight;
  final double targetWeight;
  final double startWeight;
  final String goalType;
  final String targetLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 22.0;
    final center = Offset(size.width / 2, size.height - 14);
    final radius = math.min(size.width * 0.44, size.height - 40);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Three sectors along PI..2PI (180 degrees from left to right).
    // Left dark sector: 0.0 -> 0.36 of PI
    // Center violet sector: 0.36 -> 0.64 of PI
    // Right dark sector: 0.64 -> 1.0 of PI
    const gap = 0.03;
    final leftPaint = Paint()
      ..color = AppColors.surfaceElevated
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final centerPaint = Paint()
      ..color = AppColors.weight
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final rightPaint = Paint()
      ..color = AppColors.surfaceElevated
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(rect, math.pi, math.pi * 0.36 - gap, false, leftPaint);
    canvas.drawArc(
      rect,
      math.pi + math.pi * 0.36,
      math.pi * 0.28,
      false,
      centerPaint,
    );
    canvas.drawArc(
      rect,
      math.pi + math.pi * 0.64 + gap,
      math.pi * 0.36 - gap,
      false,
      rightPaint,
    );

    // Small white triangle marker at top apex (-pi/2)
    final topY = center.dy - radius - strokeWidth / 2 - 4;
    final triPath = Path()
      ..moveTo(center.dx, topY + 6)
      ..lineTo(center.dx - 5, topY)
      ..lineTo(center.dx + 5, topY)
      ..close();
    canvas.drawPath(triPath, Paint()..color = AppColors.textPrimary);

    // Target label above triangle
    final tp = TextPainter(
      text: TextSpan(
        text: targetLabel,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, topY - tp.height - 3));

    // Map currentWeight to normalized angle t in [0.0, 1.0] (0=left, 0.5=target, 1=right)
    double t;
    if (goalType == 'maintain') {
      final delta = currentWeight - targetWeight;
      t = (0.5 + (delta / 4.0)).clamp(0.05, 0.95);
    } else {
      final span = math.max(1.5, (targetWeight - startWeight).abs());
      final deltaFromTarget = currentWeight - targetWeight;
      // Target is at 0.5 (center violet zone); normalize around target by span.
      t = (0.5 + (deltaFromTarget / (span * 2.0))).clamp(0.05, 0.95);
    }

    final angle = math.pi + t * math.pi;
    final needleLen = radius - strokeWidth / 2 - 4;
    final needleTip = Offset(
      center.dx + needleLen * math.cos(angle),
      center.dy + needleLen * math.sin(angle),
    );

    final needlePaint = Paint()
      ..color = AppColors.textPrimary
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, needleTip, needlePaint);

    // Pivot circle
    canvas.drawCircle(
      center,
      7,
      Paint()..color = AppColors.textPrimary,
    );
    canvas.drawCircle(
      center,
      3.5,
      Paint()..color = AppColors.background,
    );
  }

  @override
  bool shouldRepaint(covariant _GoalProgressGaugePainter oldDelegate) {
    return oldDelegate.currentWeight != currentWeight ||
        oldDelegate.targetWeight != targetWeight ||
        oldDelegate.startWeight != startWeight ||
        oldDelegate.goalType != goalType;
  }
}

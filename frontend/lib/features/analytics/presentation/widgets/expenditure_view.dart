import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:malvifactor/core/config/chart_preferences_provider.dart';
import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/presentation/widgets/macro_factor_chart_widgets.dart';
import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';

class ExpenditureDetailView extends ConsumerStatefulWidget {
  const ExpenditureDetailView({super.key, required this.ctx});

  final FullMetricContext ctx;

  @override
  ConsumerState<ExpenditureDetailView> createState() =>
      _ExpenditureDetailViewState();
}

class _ExpenditureDetailViewState extends ConsumerState<ExpenditureDetailView> {
  int? _scrubIndex;

  @override
  Widget build(BuildContext context) {
    final pref = ref.watch(chartPreferencesProvider(PersistedChartType.tdee));
    final range = pref.range;
    final expandedScale = pref.expandedScale;
    final points = widget.ctx.points;
    if (points.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Pas encore de données de dépense.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final windowPoints = sliceOrPadAnalyticsWindow(points, range);
    final windowCount = windowPoints.length;

    // Flux band sigma computed from historical TDEE variance (min ±55 kcal).
    final allValidTdee = points
        .map((p) => p.estimatedTdeeKcal)
        .where((v) => v > 0)
        .toList();
    double fluxSigma = 55.0;
    if (allValidTdee.length >= 2) {
      final diffs = <double>[];
      for (var i = 1; i < allValidTdee.length; i++) {
        diffs.add((allValidTdee[i] - allValidTdee[i - 1]).abs());
      }
      final mean = allValidTdee.reduce((a, b) => a + b) / allValidTdee.length;
      final variance = allValidTdee
              .map((v) => (v - mean) * (v - mean))
              .reduce((a, b) => a + b) /
          allValidTdee.length;
      fluxSigma = math.sqrt(variance).clamp(55.0, 180.0);
    }

    final tdeeSpots = <FlSpot>[];
    final upperSpots = <FlSpot>[];
    final lowerSpots = <FlSpot>[];
    final windowTdeeValues = <double>[];
    final windowYValues = <double>[];

    for (var i = 0; i < windowCount; i++) {
      final v = windowPoints[i].estimatedTdeeKcal;
      if (v > 0) {
        tdeeSpots.add(FlSpot(i.toDouble(), v));
        upperSpots.add(FlSpot(i.toDouble(), v + fluxSigma));
        lowerSpots.add(FlSpot(i.toDouble(), math.max(0.0, v - fluxSigma)));
        windowTdeeValues.add(v);
        windowYValues.add(v + fluxSigma);
        windowYValues.add(math.max(0.0, v - fluxSigma));
      }
    }

    final allHistoryY = <double>[
      for (final v in allValidTdee) ...[
        v + fluxSigma,
        math.max(0.0, v - fluxSigma),
      ],
    ];

    final activeYPool =
        expandedScale && allHistoryY.isNotEmpty ? allHistoryY : windowYValues;
    final rawMinY =
        activeYPool.isEmpty ? 1500.0 : activeYPool.reduce(math.min);
    final rawMaxY =
        activeYPool.isEmpty ? 3000.0 : activeYPool.reduce(math.max);
    final yBounds = computeCleanAxisBounds(
      rawMin: rawMinY,
      rawMax: rawMaxY,
      candidateSteps: const [50.0, 100.0, 200.0, 500.0],
      clampZero: true,
    );

    final firstVal =
        windowTdeeValues.isNotEmpty ? windowTdeeValues.first : null;
    final lastVal = windowTdeeValues.isNotEmpty ? windowTdeeValues.last : null;
    final periodAvg = windowTdeeValues.isEmpty
        ? null
        : windowTdeeValues.reduce((a, b) => a + b) / windowTdeeValues.length;
    final periodDiff =
        (firstVal != null && lastVal != null) ? lastVal - firstVal : null;

    final scrubIdx = _scrubIndex != null &&
            _scrubIndex! >= 0 &&
            _scrubIndex! < windowCount
        ? _scrubIndex!
        : null;
    final isScrubbing = scrubIdx != null;
    final scrubVal =
        scrubIdx != null && windowPoints[scrubIdx].estimatedTdeeKcal > 0
            ? windowPoints[scrubIdx].estimatedTdeeKcal
            : null;
    final scrubDiff =
        (scrubVal != null && firstVal != null) ? scrubVal - firstVal : null;

    final leftLabel = isScrubbing ? 'Dépense estimée' : 'Moyenne';
    final leftValue = isScrubbing
        ? (scrubVal != null ? '${formatFrInt(scrubVal)} kcal' : '-- kcal')
        : (periodAvg != null ? '${formatFrInt(periodAvg)} kcal' : '-- kcal');

    final rightLabel = isScrubbing ? 'Depuis début' : 'Différence';
    final shownDiff = isScrubbing ? scrubDiff : periodDiff;
    final rightValue =
        shownDiff != null ? formatFrSignedInt(shownDiff, 'kcal') : '-- kcal';
    final subtitleText = isScrubbing
        ? DateFormat('EEEE d MMM yyyy', 'fr_FR')
            .format(windowPoints[scrubIdx].date)
        : formatFrDateRange(windowPoints.first.date, windowPoints.last.date);

    final showHollowDots = windowCount <= 30;
    final xStep = math.max(1, (windowCount / 4).floor());

    final horizonRows = [3, 7, 14, 30, 90].map((h) {
      final hStart = math.max(0, points.length - h);
      final slice = [
        for (var i = hStart; i < points.length; i++)
          if (points[i].estimatedTdeeKcal > 0) points[i].estimatedTdeeKcal,
      ];
      final hasEnough = points.length >= h && slice.length >= 2;
      final delta = hasEnough ? slice.last - slice.first : null;
      return HorizonRowData(
        label: '$h jours',
        sparkValues: slice,
        delta: delta,
        deltaText: delta != null ? formatFrSignedInt(delta, 'kcal') : '--',
        stableThreshold: 15.0,
      );
    }).toList();

    final currentTdee = allValidTdee.isNotEmpty
        ? allValidTdee.last
        : widget.ctx.profile.currentTdeeKcal;
    final isCalibrated = widget.ctx.preview.confidence == 'high' ||
        widget.ctx.preview.daysLoggedCount >= 14;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Container(
          decoration: AppTheme.matteCardDecoration(),
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DynamicScrubHeader(
                      isScrubbing: isScrubbing,
                      leftLabel: leftLabel,
                      leftValue: leftValue,
                      rightLabel: rightLabel,
                      rightValue: rightValue,
                      rightColor: AppColors.expenditure,
                      subtitleText: subtitleText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ScaleToggleButton(
                    expanded: expandedScale,
                    onTap: () => ref
                        .read(chartPreferencesProvider(PersistedChartType.tdee)
                            .notifier)
                        .toggleScale(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (tdeeSpots.length < 2)
                const SizedBox(
                  height: 220,
                  child: Center(
                    child: Text(
                      'Pas encore assez de données sur cette période',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  child: RepaintBoundary(
                    key: ValueKey<String>('${range.name}_$expandedScale'),
                    child: SizedBox(
                      height: 230,
                      child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: math.max(1, windowCount - 1).toDouble(),
                      minY: yBounds.minY,
                      maxY: yBounds.maxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: yBounds.interval,
                        getDrawingHorizontalLine: (_) => const FlLine(
                          color: AppColors.border,
                          strokeWidth: 1,
                          dashArray: [4, 4],
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
                            reservedSize: 48,
                            interval: yBounds.interval,
                            getTitlesWidget: (val, _) => Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                formatFrInt(val),
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
                            interval: xStep.toDouble(),
                            getTitlesWidget: (val, meta) {
                              final idx = val.toInt();
                              if (idx < 0 || idx >= windowCount) {
                                return const SizedBox.shrink();
                              }
                              if (val != meta.max &&
                                  (meta.max - val) <
                                      meta.appliedInterval * 0.65) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  formatFrDateShort(windowPoints[idx].date),
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
                      lineTouchData: LineTouchData(
                        handleBuiltInTouches: true,
                        touchCallback: (event, response) {
                          if (event is FlPanEndEvent ||
                              event is FlTapUpEvent ||
                              event is FlLongPressEnd ||
                              event is FlPointerExitEvent) {
                            if (_scrubIndex != null) {
                              setState(() => _scrubIndex = null);
                            }
                            return;
                          }
                          final spots = response?.lineBarSpots;
                          if (spots == null || spots.isEmpty) return;
                          final idx = spots.first.x.round().clamp(
                                0,
                                windowCount - 1,
                              );
                          if (_scrubIndex != idx) {
                            setState(() => _scrubIndex = idx);
                          }
                        },
                        getTouchedSpotIndicator: (barData, spotIndexes) {
                          if (barData.color != AppColors.expenditure) {
                            return spotIndexes.map((_) => null).toList();
                          }
                          return spotIndexes.map((_) {
                            return TouchedSpotIndicatorData(
                              const FlLine(
                                color: AppColors.textSecondary,
                                strokeWidth: 1.2,
                                dashArray: [4, 4],
                              ),
                              FlDotData(
                                show: true,
                                getDotPainter: (_, __, ___, ____) =>
                                    FlDotCirclePainter(
                                  radius: 5,
                                  color: AppColors.background,
                                  strokeWidth: 2.5,
                                  strokeColor: AppColors.expenditure,
                                ),
                              ),
                            );
                          }).toList();
                        },
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => Colors.transparent,
                          tooltipPadding: EdgeInsets.zero,
                          getTooltipItems: (spots) =>
                              spots.map((_) => null).toList(),
                        ),
                      ),
                      betweenBarsData: [
                        if (upperSpots.length >= 2 && lowerSpots.length >= 2)
                          BetweenBarsData(
                            fromIndex: 0,
                            toIndex: 1,
                            color:
                                AppColors.expenditure.withValues(alpha: 0.15),
                          ),
                      ],
                      lineBarsData: [
                        // 0: Upper flux band
                        LineChartBarData(
                          spots: upperSpots,
                          isCurved: true,
                          curveSmoothness: 0.15,
                          preventCurveOverShooting: true,
                          color: Colors.transparent,
                          barWidth: 0,
                          dotData: const FlDotData(show: false),
                        ),
                        // 1: Lower flux band
                        LineChartBarData(
                          spots: lowerSpots,
                          isCurved: true,
                          curveSmoothness: 0.15,
                          preventCurveOverShooting: true,
                          color: Colors.transparent,
                          barWidth: 0,
                          dotData: const FlDotData(show: false),
                        ),
                        // 2: Expenditure TDEE line
                        LineChartBarData(
                          spots: tdeeSpots,
                          isCurved: true,
                          curveSmoothness: 0.15,
                          preventCurveOverShooting: true,
                          color: AppColors.expenditure,
                          barWidth: 2.6,
                          dotData: FlDotData(
                            show: showHollowDots,
                            getDotPainter: (_, __, ___, ____) =>
                                FlDotCirclePainter(
                              radius: 3.3,
                              color: AppColors.background,
                              strokeWidth: 2.0,
                              strokeColor: AppColors.expenditure,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PeriodPillsBar(
          selected: range,
          onChanged: (r) {
            ref
                .read(chartPreferencesProvider(PersistedChartType.tdee)
                    .notifier)
                .setRange(r);
            if (_scrubIndex != null) setState(() => _scrubIndex = null);
          },
        ),
        const SizedBox(height: 10),
        const ChartLegendCard(
          items: [
            ChartLegendItemData(
              label: 'Plage de flux',
              color: AppColors.expenditure,
              kind: LegendSwatchKind.band,
            ),
            ChartLegendItemData(
              label: 'Dépense (TDEE)',
              color: AppColors.expenditure,
              kind: LegendSwatchKind.hollowLine,
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Analyses & Données',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        HorizonEvolutionCard(
          title: 'Évolution de la dépense',
          accentColor: AppColors.expenditure,
          rows: horizonRows,
        ),
        const SizedBox(height: 12),
        AnalysisMetricCard(
          valueText: '${formatFrInt(currentTdee)} kcal',
          valueColor: AppColors.expenditure,
          title: 'Dépense actuelle',
          description:
              'Dernière estimation de votre dépense énergétique quotidienne basée sur votre tendance de poids et vos apports.',
        ),
        const SizedBox(height: 10),
        AnalysisMetricCard(
          valueText: isCalibrated ? 'Calibré' : 'En actualisation',
          valueColor: isCalibrated ? AppColors.carbs : AppColors.fat,
          title: 'Statut de l’algorithme',
          description:
              'Qualité et complétude des données sur la fenêtre glissante de 21 jours (${widget.ctx.preview.daysLoggedCount} jours valides).',
        ),
      ],
    );
  }
}

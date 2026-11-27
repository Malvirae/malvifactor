import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/presentation/widgets/macro_factor_chart_widgets.dart';
import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';

class WeightTrendDetailView extends StatefulWidget {
  const WeightTrendDetailView({super.key, required this.ctx});

  final FullMetricContext ctx;

  @override
  State<WeightTrendDetailView> createState() => _WeightTrendDetailViewState();
}

class _WeightTrendDetailViewState extends State<WeightTrendDetailView> {
  AnalyticsRange _range = AnalyticsRange.m1;
  bool _expandedScale = false;
  int? _scrubIndex;

  @override
  Widget build(BuildContext context) {
    final points = widget.ctx.points;
    if (points.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Pas encore de données de poids.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final series = _buildDailyTrendSeries(points);
    final windowPoints = sliceOrPadAnalyticsWindow(points, _range);
    final windowCount = windowPoints.length;
    final offset = windowCount - points.length;

    final trendSpots = <FlSpot>[];
    final upperSpots = <FlSpot>[];
    final lowerSpots = <FlSpot>[];
    final rawSpots = <FlSpot>[];
    final actualWeighInXs = <int>{};

    final windowTrendValues = <double>[];
    final windowYValues = <double>[];

    for (var i = 0; i < windowCount; i++) {
      final globalIdx = i - offset;
      if (globalIdx < 0 || globalIdx >= points.length) continue;
      final trend = series.interpolatedTrend[globalIdx];
      final raw = windowPoints[i].weightKg;
      if (trend != null) {
        trendSpots.add(FlSpot(i.toDouble(), trend));
        upperSpots.add(FlSpot(i.toDouble(), trend + series.noiseSigma));
        lowerSpots.add(FlSpot(i.toDouble(), trend - series.noiseSigma));
        windowTrendValues.add(trend);
        windowYValues.add(trend + series.noiseSigma);
        windowYValues.add(trend - series.noiseSigma);
      }
      if (raw != null) {
        actualWeighInXs.add(i);
        rawSpots.add(FlSpot(i.toDouble(), raw));
        windowYValues.add(raw);
      }
    }

    final allHistoryY = <double>[];
    for (var i = 0; i < points.length; i++) {
      final t = series.interpolatedTrend[i];
      if (t != null) {
        allHistoryY.add(t + series.noiseSigma);
        allHistoryY.add(t - series.noiseSigma);
      }
      if (points[i].weightKg != null) {
        allHistoryY.add(points[i].weightKg!);
      }
    }

    final activeYPool =
        _expandedScale && allHistoryY.isNotEmpty ? allHistoryY : windowYValues;
    final rawMinY =
        activeYPool.isEmpty ? 60.0 : activeYPool.reduce(math.min);
    final rawMaxY =
        activeYPool.isEmpty ? 85.0 : activeYPool.reduce(math.max);
    final yBounds = computeCleanAxisBounds(
      rawMin: rawMinY,
      rawMax: rawMaxY,
      candidateSteps: const [0.5, 1.0, 2.0, 5.0, 10.0],
    );

    final firstWindowTrend =
        windowTrendValues.isNotEmpty ? windowTrendValues.first : null;
    final lastWindowTrend =
        windowTrendValues.isNotEmpty ? windowTrendValues.last : null;
    final periodAvg = windowTrendValues.isEmpty
        ? null
        : windowTrendValues.reduce((a, b) => a + b) / windowTrendValues.length;
    final periodDiff = (firstWindowTrend != null && lastWindowTrend != null)
        ? lastWindowTrend - firstWindowTrend
        : null;

    // Header values (dynamic scrubbing vs period summary)
    final scrubIdx = _scrubIndex != null &&
            _scrubIndex! >= 0 &&
            _scrubIndex! < windowCount
        ? _scrubIndex!
        : null;
    final isScrubbing = scrubIdx != null;
    final scrubGlobalIdx = scrubIdx != null ? scrubIdx - offset : null;
    final scrubTrend = (scrubGlobalIdx != null &&
            scrubGlobalIdx >= 0 &&
            scrubGlobalIdx < points.length)
        ? series.interpolatedTrend[scrubGlobalIdx]
        : null;
    final scrubRaw = scrubIdx != null ? windowPoints[scrubIdx].weightKg : null;
    final scrubDiff = (scrubTrend != null && firstWindowTrend != null)
        ? scrubTrend - firstWindowTrend
        : null;

    final leftLabel = isScrubbing ? 'Tendance de poids' : 'Moyenne';
    final leftValue = isScrubbing
        ? (scrubTrend != null
            ? '${formatFrDecimal(scrubTrend, 1)} kg'
            : '-- kg')
        : (periodAvg != null
            ? '${formatFrDecimal(periodAvg, 1)} kg'
            : '-- kg');
    final leftSubValue = (isScrubbing && scrubRaw != null)
        ? 'Brut : ${formatFrDecimal(scrubRaw, 1)} kg'
        : null;

    final rightLabel = isScrubbing ? 'Depuis début' : 'Différence';
    final shownDiff = isScrubbing ? scrubDiff : periodDiff;
    final rightValue = shownDiff != null
        ? formatFrSignedDecimal(shownDiff, 1, 'kg')
        : '-- kg';
    final subtitleText = isScrubbing
        ? DateFormat('EEEE d MMM yyyy', 'fr_FR')
            .format(windowPoints[scrubIdx].date)
        : formatFrDateRange(windowPoints.first.date, windowPoints.last.date);

    final showHollowDots = windowCount <= 30;
    final xStep = math.max(1, (windowCount / 4).floor());

    // Analytics metrics
    final currentTrend = series.latestTrend;
    final weeklyRate = _computeWeightedWeeklyRate(series.interpolatedTrend);
    final dailyBalanceKcal = weeklyRate != null ? weeklyRate * 7700.0 / 7.0 : null;
    final projected30d = (currentTrend != null && weeklyRate != null)
        ? currentTrend + weeklyRate * (30.0 / 7.0)
        : null;

    final horizonRows = [3, 7, 14, 30, 90].map((h) {
      final hStart = math.max(0, points.length - h);
      final slice = [
        for (var i = hStart; i < points.length; i++)
          if (series.interpolatedTrend[i] != null) series.interpolatedTrend[i]!,
      ];
      final hasEnough = points.length >= h && slice.length >= 2;
      final delta = hasEnough ? slice.last - slice.first : null;
      return HorizonRowData(
        label: '$h jours',
        sparkValues: slice,
        delta: delta,
        deltaText:
            delta != null ? formatFrSignedDecimal(delta, 1, 'kg') : '--',
        stableThreshold: 0.05,
      );
    }).toList();

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
                      leftSubValue: leftSubValue,
                      rightLabel: rightLabel,
                      rightValue: rightValue,
                      rightColor: AppColors.weight,
                      subtitleText: subtitleText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ScaleToggleButton(
                    expanded: _expandedScale,
                    onTap: () =>
                        setState(() => _expandedScale = !_expandedScale),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (trendSpots.length < 2 && rawSpots.length < 2)
                const SizedBox(
                  height: 220,
                  child: Center(
                    child: Text(
                      'Pas encore assez de pesées sur cette période',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                SizedBox(
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
                            reservedSize: 44,
                            interval: yBounds.interval,
                            getTitlesWidget: (val, meta) {
                              if ((val - meta.min).abs() < 1e-6 ||
                                  (val - meta.max).abs() < 1e-6) {
                                return Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    formatFrDecimal(val, 1),
                                    style: AppTheme.numericStyle(
                                      fontSize: 10,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Text(
                                  formatFrDecimal(val, 1),
                                  style: AppTheme.numericStyle(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              );
                            },
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
                          if (barData.color != AppColors.weight) {
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
                                  strokeColor: AppColors.weight,
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
                            color: AppColors.weight.withValues(alpha: 0.15),
                          ),
                      ],
                      lineBarsData: [
                        // 0: Upper noise band
                        LineChartBarData(
                          spots: upperSpots,
                          isCurved: true,
                          curveSmoothness: 0.15,
                          preventCurveOverShooting: true,
                          color: Colors.transparent,
                          barWidth: 0,
                          dotData: const FlDotData(show: false),
                        ),
                        // 1: Lower noise band
                        LineChartBarData(
                          spots: lowerSpots,
                          isCurved: true,
                          curveSmoothness: 0.15,
                          preventCurveOverShooting: true,
                          color: Colors.transparent,
                          barWidth: 0,
                          dotData: const FlDotData(show: false),
                        ),
                        // 2: Tendance de poids curve
                        LineChartBarData(
                          spots: trendSpots,
                          isCurved: true,
                          curveSmoothness: 0.15,
                          preventCurveOverShooting: true,
                          color: AppColors.weight,
                          barWidth: 2.6,
                          dotData: FlDotData(
                            show: showHollowDots,
                            checkToShowDot: (spot, _) =>
                                actualWeighInXs.contains(spot.x.round()),
                            getDotPainter: (_, __, ___, ____) =>
                                FlDotCirclePainter(
                              radius: 3.4,
                              color: AppColors.background,
                              strokeWidth: 2.0,
                              strokeColor: AppColors.weight,
                            ),
                          ),
                        ),
                        // 3: Poids brut scattered solid dots
                        if (rawSpots.isNotEmpty)
                          LineChartBarData(
                            spots: rawSpots,
                            isCurved: false,
                            color: Colors.transparent,
                            barWidth: 0,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (_, __, ___, ____) =>
                                  FlDotCirclePainter(
                                radius: 2.5,
                                color: AppColors.weight,
                                strokeWidth: 0,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PeriodPillsBar(
          selected: _range,
          onChanged: (r) => setState(() {
            _range = r;
            _scrubIndex = null;
          }),
        ),
        const SizedBox(height: 10),
        const ChartLegendCard(
          items: [
            ChartLegendItemData(
              label: 'Plage de bruit',
              color: AppColors.weight,
              kind: LegendSwatchKind.band,
            ),
            ChartLegendItemData(
              label: 'Tendance de poids',
              color: AppColors.weight,
              kind: LegendSwatchKind.hollowLine,
            ),
            ChartLegendItemData(
              label: 'Poids brut',
              color: AppColors.weight,
              kind: LegendSwatchKind.solidDot,
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
          title: 'Évolution du poids',
          accentColor: AppColors.weight,
          rows: horizonRows,
        ),
        const SizedBox(height: 12),
        AnalysisMetricCard(
          valueText: currentTrend != null
              ? '${formatFrDecimal(currentTrend, 1)} kg'
              : '-- kg',
          valueColor: AppColors.weight,
          title: 'Tendance de poids actuelle',
          description:
              'Estimation de votre poids réel après lissage des fluctuations quotidiennes.',
        ),
        const SizedBox(height: 10),
        AnalysisMetricCard(
          valueText: weeklyRate != null
              ? '${formatFrSignedDecimal(weeklyRate, 2, 'kg')} / sem.'
              : '-- kg / sem.',
          title: 'Variation hebdomadaire',
          description:
              'Rythme hebdomadaire moyen sur les 3 dernières semaines, pondéré vers les pesées récentes.',
        ),
        const SizedBox(height: 10),
        AnalysisMetricCard(
          valueText: dailyBalanceKcal != null
              ? '${formatFrSignedInt(dailyBalanceKcal, 'kcal')} / j'
              : '-- kcal / j',
          title: 'Déficit / Surplus énergétique',
          description:
              'Estimation de votre bilan calorique quotidien moyen déduit de l’évolution de votre tendance de poids.',
        ),
        const SizedBox(height: 10),
        AnalysisMetricCard(
          valueText: projected30d != null
              ? '${formatFrDecimal(projected30d, 1)} kg'
              : '-- kg',
          title: 'Projection à 30 jours',
          description:
              'Tendance de poids estimée dans 30 jours au rythme actuel.',
        ),
      ],
    );
  }
}

class _DailyTrendSeries {
  const _DailyTrendSeries({
    required this.interpolatedTrend,
    required this.noiseSigma,
    required this.latestTrend,
  });

  final List<double?> interpolatedTrend;
  final double noiseSigma;
  final double? latestTrend;
}

_DailyTrendSeries _buildDailyTrendSeries(List<AnalyticsPointModel> points) {
  final rawTrend = List<double?>.generate(
    points.length,
    (i) => points[i].trendWeightKg ?? points[i].weightKg,
  );
  final knownIndices = <int>[
    for (var i = 0; i < rawTrend.length; i++)
      if (rawTrend[i] != null) i,
  ];

  final interpolated = List<double?>.filled(points.length, null);
  if (knownIndices.isNotEmpty) {
    for (var k = 0; k < knownIndices.length; k++) {
      final idx = knownIndices[k];
      interpolated[idx] = rawTrend[idx];
      if (k + 1 < knownIndices.length) {
        final nextIdx = knownIndices[k + 1];
        final startVal = rawTrend[idx]!;
        final endVal = rawTrend[nextIdx]!;
        final span = nextIdx - idx;
        for (var j = 1; j < span; j++) {
          interpolated[idx + j] = startVal + (endVal - startVal) * (j / span);
        }
      }
    }
  }

  final residuals = <double>[];
  for (final p in points) {
    if (p.weightKg != null && p.trendWeightKg != null) {
      residuals.add(p.weightKg! - p.trendWeightKg!);
    }
  }

  double sigma = 0.35;
  if (residuals.length >= 2) {
    final mean = residuals.reduce((a, b) => a + b) / residuals.length;
    final variance = residuals
            .map((r) => (r - mean) * (r - mean))
            .reduce((a, b) => a + b) /
        residuals.length;
    sigma = math.sqrt(variance).clamp(0.25, 2.2);
  }

  final latestTrend =
      knownIndices.isNotEmpty ? rawTrend[knownIndices.last] : null;

  return _DailyTrendSeries(
    interpolatedTrend: interpolated,
    noiseSigma: sigma,
    latestTrend: latestTrend,
  );
}

double? _computeWeightedWeeklyRate(List<double?> dailyTrends) {
  final start = math.max(0, dailyTrends.length - 21);
  final valid = <MapEntry<int, double>>[];
  for (var i = start; i < dailyTrends.length; i++) {
    final v = dailyTrends[i];
    if (v != null) {
      valid.add(MapEntry(i - start, v));
    }
  }
  if (valid.length < 2) return null;

  // Weighted linear regression giving higher weight to recent days.
  double sumW = 0;
  double sumWX = 0;
  double sumWY = 0;
  double sumWXX = 0;
  double sumWXY = 0;

  for (final entry in valid) {
    final x = entry.key.toDouble();
    final y = entry.value;
    final w = 1.0 + (x / 21.0) * 2.0; // linear recency weighting [1..3]
    sumW += w;
    sumWX += w * x;
    sumWY += w * y;
    sumWXX += w * x * x;
    sumWXY += w * x * y;
  }

  final denom = sumW * sumWXX - sumWX * sumWX;
  if (denom.abs() < 1e-6) return 0.0;
  final slopePerDay = (sumW * sumWXY - sumWX * sumWY) / denom;
  return slopePerDay * 7.0;
}

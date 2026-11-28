import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:malvifactor/core/config/chart_preferences_provider.dart';
import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/presentation/widgets/macro_factor_chart_widgets.dart';
import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';

class BodyFatDetailView extends ConsumerStatefulWidget {
  const BodyFatDetailView({super.key, required this.ctx});

  final FullMetricContext ctx;

  @override
  ConsumerState<BodyFatDetailView> createState() => _BodyFatDetailViewState();
}

class _BodyFatDetailViewState extends ConsumerState<BodyFatDetailView> {
  int? _scrubIndex;

  @override
  Widget build(BuildContext context) {
    final pref = ref.watch(chartPreferencesProvider(PersistedChartType.bodyFat));
    final range = pref.range;
    final expandedScale = pref.expandedScale;
    final points = widget.ctx.points;
    final allWeights = widget.ctx.allWeights;
    final fatWeights = allWeights.where((w) => w.bodyFatPct != null).toList();

    if (points.isEmpty || fatWeights.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Pas encore de mesures de masse grasse.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final windowPoints = sliceOrPadAnalyticsWindow(points, range);
    final windowCount = windowPoints.length;

    final fatSeries = _buildDailyBodyFatSeries(points, fatWeights);
    final offset = windowCount - points.length;

    final smoothedSpots = <FlSpot>[];
    final upperSpots = <FlSpot>[];
    final lowerSpots = <FlSpot>[];
    final rawSpots = <FlSpot>[];
    final actualMeasureXs = <int>{};
    final rawByWindowIdx = <int, double>{};

    final windowSmoothedValues = <double>[];
    final windowYValues = <double>[];

    for (var i = 0; i < windowCount; i++) {
      final globalIdx = i - offset;
      if (globalIdx < 0 || globalIdx >= points.length) continue;

      final smoothed = fatSeries.interpolatedSmoothed[globalIdx];
      final raw = fatSeries.rawByGlobalIdx[globalIdx];

      if (smoothed != null) {
        smoothedSpots.add(FlSpot(i.toDouble(), smoothed));
        final upper = smoothed + fatSeries.noiseSigma;
        final lower = math.max(0.0, smoothed - fatSeries.noiseSigma);
        upperSpots.add(FlSpot(i.toDouble(), upper));
        lowerSpots.add(FlSpot(i.toDouble(), lower));
        windowSmoothedValues.add(smoothed);
        windowYValues.add(upper);
        windowYValues.add(lower);
      }
      if (raw != null) {
        actualMeasureXs.add(i);
        rawByWindowIdx[i] = raw;
        rawSpots.add(FlSpot(i.toDouble(), raw));
        windowYValues.add(raw);
      }
    }

    final allHistoryY = <double>[];
    for (var i = 0; i < points.length; i++) {
      final s = fatSeries.interpolatedSmoothed[i];
      if (s != null) {
        allHistoryY.add(s + fatSeries.noiseSigma);
        allHistoryY.add(math.max(0.0, s - fatSeries.noiseSigma));
      }
      final r = fatSeries.rawByGlobalIdx[i];
      if (r != null) {
        allHistoryY.add(r);
      }
    }

    final activeYPool =
        expandedScale && allHistoryY.isNotEmpty ? allHistoryY : windowYValues;
    final rawMinY =
        activeYPool.isEmpty ? 5.0 : activeYPool.reduce(math.min);
    final rawMaxY =
        activeYPool.isEmpty ? 30.0 : activeYPool.reduce(math.max);
    final yBounds = computeCleanAxisBounds(
      rawMin: rawMinY,
      rawMax: rawMaxY,
      candidateSteps: const [0.5, 1.0, 2.0, 5.0],
      clampZero: true,
    );

    final firstWindowVal =
        windowSmoothedValues.isNotEmpty ? windowSmoothedValues.first : null;
    final lastWindowVal =
        windowSmoothedValues.isNotEmpty ? windowSmoothedValues.last : null;
    final periodAvg = windowSmoothedValues.isEmpty
        ? null
        : windowSmoothedValues.reduce((a, b) => a + b) /
            windowSmoothedValues.length;
    final periodDiff = (firstWindowVal != null && lastWindowVal != null)
        ? lastWindowVal - firstWindowVal
        : null;

    final scrubIdx = _scrubIndex != null &&
            _scrubIndex! >= 0 &&
            _scrubIndex! < windowCount
        ? _scrubIndex!
        : null;
    final isScrubbing = scrubIdx != null;
    final scrubGlobalIdx = scrubIdx != null ? scrubIdx - offset : null;
    final scrubSmoothed = (scrubGlobalIdx != null &&
            scrubGlobalIdx >= 0 &&
            scrubGlobalIdx < points.length)
        ? fatSeries.interpolatedSmoothed[scrubGlobalIdx]
        : null;
    final scrubRaw = scrubIdx != null ? rawByWindowIdx[scrubIdx] : null;
    final scrubDiff = (scrubSmoothed != null && firstWindowVal != null)
        ? scrubSmoothed - firstWindowVal
        : null;

    final leftLabel = isScrubbing ? 'Masse grasse (lissé)' : 'Moyenne';
    final leftValue = isScrubbing
        ? (scrubSmoothed != null
            ? '${formatFrDecimal(scrubSmoothed, 1)} %'
            : '-- %')
        : (periodAvg != null
            ? '${formatFrDecimal(periodAvg, 1)} %'
            : '-- %');
    final leftSubValue = (isScrubbing && scrubRaw != null)
        ? 'Brut : ${formatFrDecimal(scrubRaw, 1)} %'
        : null;

    final rightLabel = isScrubbing ? 'Depuis début' : 'Différence';
    final shownDiff = isScrubbing ? scrubDiff : periodDiff;
    final rightValue =
        shownDiff != null ? formatFrSignedDecimal(shownDiff, 1, '%') : '-- %';
    final subtitleText = isScrubbing
        ? DateFormat('EEEE d MMM yyyy', 'fr_FR')
            .format(windowPoints[scrubIdx].date)
        : formatFrDateRange(windowPoints.first.date, windowPoints.last.date);

    final showHollowDots = windowCount <= 30;
    final xStep = math.max(1, (windowCount / 4).floor());

    // Analytics metrics
    final currentPct = fatSeries.latestSmoothed;
    final latestTrendWeightKg = _latestTrendWeightKg(points, allWeights);
    final fatMassKg = (currentPct != null && latestTrendWeightKg != null)
        ? latestTrendWeightKg * (currentPct / 100.0)
        : null;
    final leanMassKg = (currentPct != null && latestTrendWeightKg != null)
        ? latestTrendWeightKg * (1.0 - currentPct / 100.0)
        : null;
    final weeklyRate =
        _computeBodyFatWeeklyRate(fatSeries.interpolatedSmoothed);

    final horizonRows = [3, 7, 14, 30, 90].map((h) {
      final hStart = math.max(0, points.length - h);
      final slice = [
        for (var i = hStart; i < points.length; i++)
          if (fatSeries.interpolatedSmoothed[i] != null)
            fatSeries.interpolatedSmoothed[i]!,
      ];
      final hasEnough = points.length >= h && slice.length >= 2;
      final delta = hasEnough ? slice.last - slice.first : null;
      return HorizonRowData(
        label: '$h jours',
        sparkValues: slice,
        delta: delta,
        deltaText: delta != null ? formatFrSignedDecimal(delta, 1, '%') : '--',
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
                      rightColor: AppColors.bodyFat,
                      subtitleText: subtitleText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ScaleToggleButton(
                    expanded: expandedScale,
                    onTap: () => ref
                        .read(chartPreferencesProvider(PersistedChartType.bodyFat)
                            .notifier)
                        .toggleScale(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (smoothedSpots.length < 2 && rawSpots.length < 2)
                const SizedBox(
                  height: 220,
                  child: Center(
                    child: Text(
                      'Pas encore assez de mesures sur cette période',
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
                            getTitlesWidget: (val, _) => Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                '${formatFrDecimal(val, 1)}%',
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
                          if (barData.color != AppColors.bodyFat) {
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
                                  strokeColor: AppColors.bodyFat,
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
                            color: AppColors.bodyFat.withValues(alpha: 0.15),
                          ),
                      ],
                      lineBarsData: [
                        // 0: Upper uncertainty band
                        LineChartBarData(
                          spots: upperSpots,
                          isCurved: true,
                          curveSmoothness: 0.15,
                          preventCurveOverShooting: true,
                          color: Colors.transparent,
                          barWidth: 0,
                          dotData: const FlDotData(show: false),
                        ),
                        // 1: Lower uncertainty band
                        LineChartBarData(
                          spots: lowerSpots,
                          isCurved: true,
                          curveSmoothness: 0.15,
                          preventCurveOverShooting: true,
                          color: Colors.transparent,
                          barWidth: 0,
                          dotData: const FlDotData(show: false),
                        ),
                        // 2: Smoothed body-fat curve
                        LineChartBarData(
                          spots: smoothedSpots,
                          isCurved: true,
                          curveSmoothness: 0.15,
                          preventCurveOverShooting: true,
                          color: AppColors.bodyFat,
                          barWidth: 2.6,
                          dotData: FlDotData(
                            show: showHollowDots,
                            checkToShowDot: (spot, _) =>
                                actualMeasureXs.contains(spot.x.round()),
                            getDotPainter: (_, __, ___, ____) =>
                                FlDotCirclePainter(
                              radius: 3.4,
                              color: AppColors.background,
                              strokeWidth: 2.0,
                              strokeColor: AppColors.bodyFat,
                            ),
                          ),
                        ),
                        // 3: Raw body-fat dots
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
                                color: AppColors.bodyFat,
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
          selected: range,
          onChanged: (r) {
            ref
                .read(chartPreferencesProvider(PersistedChartType.bodyFat)
                    .notifier)
                .setRange(r);
            if (_scrubIndex != null) setState(() => _scrubIndex = null);
          },
        ),
        const SizedBox(height: 10),
        const ChartLegendCard(
          items: [
            ChartLegendItemData(
              label: 'Plage de bruit',
              color: AppColors.bodyFat,
              kind: LegendSwatchKind.band,
            ),
            ChartLegendItemData(
              label: 'Masse grasse (lissé)',
              color: AppColors.bodyFat,
              kind: LegendSwatchKind.hollowLine,
            ),
            ChartLegendItemData(
              label: 'Mesures brutes',
              color: AppColors.bodyFat,
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
          title: 'Évolution de la masse grasse',
          accentColor: AppColors.bodyFat,
          rows: horizonRows,
        ),
        const SizedBox(height: 12),
        AnalysisMetricCard(
          valueText: currentPct != null
              ? '${formatFrDecimal(currentPct, 1)} %'
              : '-- %',
          valueColor: AppColors.bodyFat,
          title: 'Masse grasse actuelle',
          description: 'Dernier taux de masse grasse lissé mesuré.',
        ),
        const SizedBox(height: 10),
        AnalysisMetricCard(
          valueText: fatMassKg != null
              ? '${formatFrDecimal(fatMassKg, 1)} kg'
              : '-- kg',
          title: 'Masse grasse (kg)',
          description: 'Estimation de votre masse adipeuse totale.',
        ),
        const SizedBox(height: 10),
        AnalysisMetricCard(
          valueText: leanMassKg != null
              ? '${formatFrDecimal(leanMassKg, 1)} kg'
              : '-- kg',
          title: 'Masse maigre (kg)',
          description:
              'Estimation de votre masse non grasse (muscles, os, eau).',
        ),
        const SizedBox(height: 10),
        AnalysisMetricCard(
          valueText: weeklyRate != null
              ? '${formatFrSignedDecimal(weeklyRate, 2, '%')} / sem.'
              : '-- % / sem.',
          title: 'Variation hebdomadaire',
          description: 'Rythme moyen d’évolution sur les 3 dernières semaines.',
        ),
      ],
    );
  }
}

class _DailyBodyFatSeries {
  const _DailyBodyFatSeries({
    required this.interpolatedSmoothed,
    required this.rawByGlobalIdx,
    required this.noiseSigma,
    required this.latestSmoothed,
  });

  final List<double?> interpolatedSmoothed;
  final Map<int, double> rawByGlobalIdx;
  final double noiseSigma;
  final double? latestSmoothed;
}

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

_DailyBodyFatSeries _buildDailyBodyFatSeries(
  List<AnalyticsPointModel> points,
  List<WeightEntryModel> fatWeights,
) {
  final rawByDayKey = <String, double>{};
  for (final w in fatWeights) {
    if (w.bodyFatPct != null) {
      rawByDayKey[_dayKey(w.measuredAt.toLocal())] = w.bodyFatPct!;
    }
  }

  final rawByGlobalIdx = <int, double>{};
  final ewmaByGlobalIdx = List<double?>.filled(points.length, null);

  double? ewma;
  int? lastIdx;
  final residuals = <double>[];

  for (var i = 0; i < points.length; i++) {
    final key = _dayKey(points[i].date);
    final raw = rawByDayKey[key];
    if (raw != null) {
      rawByGlobalIdx[i] = raw;
      if (ewma == null || lastIdx == null) {
        ewma = raw;
      } else {
        final deltaDays = math.max(1, i - lastIdx).toDouble();
        final alphaEff = 1.0 - math.pow(1.0 - 0.12, deltaDays);
        ewma = ewma + alphaEff * (raw - ewma);
      }
      ewmaByGlobalIdx[i] = ewma;
      residuals.add(raw - ewma);
      lastIdx = i;
    }
  }

  final knownIndices = <int>[
    for (var i = 0; i < ewmaByGlobalIdx.length; i++)
      if (ewmaByGlobalIdx[i] != null) i,
  ];
  final interpolated = List<double?>.filled(points.length, null);
  for (var k = 0; k < knownIndices.length; k++) {
    final idx = knownIndices[k];
    interpolated[idx] = ewmaByGlobalIdx[idx];
    if (k + 1 < knownIndices.length) {
      final nextIdx = knownIndices[k + 1];
      final startVal = ewmaByGlobalIdx[idx]!;
      final endVal = ewmaByGlobalIdx[nextIdx]!;
      final span = nextIdx - idx;
      for (var j = 1; j < span; j++) {
        interpolated[idx + j] = startVal + (endVal - startVal) * (j / span);
      }
    }
  }

  double sigma = 0.25;
  if (residuals.length >= 2) {
    final mean = residuals.reduce((a, b) => a + b) / residuals.length;
    final variance = residuals
            .map((r) => (r - mean) * (r - mean))
            .reduce((a, b) => a + b) /
        residuals.length;
    sigma = math.sqrt(variance).clamp(0.2, 1.8);
  }

  final latestSmoothed =
      knownIndices.isNotEmpty ? ewmaByGlobalIdx[knownIndices.last] : null;

  return _DailyBodyFatSeries(
    interpolatedSmoothed: interpolated,
    rawByGlobalIdx: rawByGlobalIdx,
    noiseSigma: sigma,
    latestSmoothed: latestSmoothed,
  );
}

double? _latestTrendWeightKg(
  List<AnalyticsPointModel> points,
  List<WeightEntryModel> allWeights,
) {
  for (var i = points.length - 1; i >= 0; i--) {
    final t = points[i].trendWeightKg ?? points[i].weightKg;
    if (t != null) return t;
  }
  if (allWeights.isNotEmpty) {
    final last = allWeights.last;
    return last.trendWeightKg ?? last.weightKg;
  }
  return null;
}

double? _computeBodyFatWeeklyRate(List<double?> dailySmoothed) {
  final start = math.max(0, dailySmoothed.length - 21);
  final valid = <MapEntry<int, double>>[];
  for (var i = start; i < dailySmoothed.length; i++) {
    final v = dailySmoothed[i];
    if (v != null) valid.add(MapEntry(i - start, v));
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

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';
import 'package:malvifactor/features/profile/providers/profile_provider.dart';

final analyticsDaysProvider = StateProvider<int>((ref) => 30);

final analyticsSeriesProvider =
    FutureProvider<List<AnalyticsPointModel>>((ref) async {
  final days = ref.watch(analyticsDaysProvider);
  return ref.watch(dashboardRepositoryProvider).fetchAnalytics(days);
});

class AnalyticsDetailScreen extends ConsumerWidget {
  const AnalyticsDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(analyticsDaysProvider);
    final seriesAsync = ref.watch(analyticsSeriesProvider);
    final profileAsync = ref.watch(profileProvider);
    final calorieTarget =
        profileAsync.valueOrNull?.currentCalorieTarget ?? 2000.0;

    return Scaffold(
      appBar: AppBar(title: const Text('ANALYSES DÉTAILLÉES')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7J')),
                ButtonSegment(value: 14, label: Text('14J')),
                ButtonSegment(value: 30, label: Text('30J')),
                ButtonSegment(value: 90, label: Text('90J')),
              ],
              selected: {days},
              onSelectionChanged: (sel) =>
                  ref.read(analyticsDaysProvider.notifier).state = sel.first,
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.calories,
              backgroundColor: AppColors.surface,
              onRefresh: () => ref.refresh(analyticsSeriesProvider.future),
              child: seriesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.calories),
                ),
                error: (e, _) => ListView(
                  padding: const EdgeInsets.all(20),
                  children: [Text('Erreur : $e')],
                ),
                data: (points) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  children: [
                    _WeightChartCard(points: points),
                    const SizedBox(height: 14),
                    _TdeeChartCard(points: points),
                    const SizedBox(height: 14),
                    _IntakeChartCard(
                      points: points,
                      calorieTarget: calorieTarget,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightChartCard extends StatelessWidget {
  const _WeightChartCard({required this.points});

  final List<AnalyticsPointModel> points;

  @override
  Widget build(BuildContext context) {
    final rawSpots = <FlSpot>[];
    final trendSpots = <FlSpot>[];
    final values = <double>[];

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.weightKg != null) {
        rawSpots.add(FlSpot(i.toDouble(), p.weightKg!));
        values.add(p.weightKg!);
      }
      if (p.trendWeightKg != null) {
        trendSpots.add(FlSpot(i.toDouble(), p.trendWeightKg!));
        values.add(p.trendWeightKg!);
      }
    }

    final minY = values.isEmpty ? 60.0 : (values.reduce(math.min) - 1.5);
    final maxY = values.isEmpty ? 90.0 : (values.reduce(math.max) + 1.5);

    return Container(
      decoration: AppTheme.matteCardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Poids brut vs Tendance EWMA',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Points : poids mesuré · Courbe violette : tendance lissée',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: values.isEmpty
                ? const Center(
                    child: Text(
                      'Aucune pesée sur cette période',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minY: minY,
                      maxY: maxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => const FlLine(
                          color: AppColors.border,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: _buildDateTitles(points),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => AppColors.surfaceElevated,
                          getTooltipItems: (spots) => spots.map((s) {
                            final idx = s.x.toInt();
                            final dateLabel = idx >= 0 && idx < points.length
                                ? DateFormat('dd/MM').format(points[idx].date)
                                : '';
                            return LineTooltipItem(
                              '$dateLabel : ${s.y.toStringAsFixed(1)} kg',
                              AppTheme.numericStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      lineBarsData: [
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
                                radius: 3.2,
                                color: AppColors.textSecondary,
                                strokeWidth: 0,
                              ),
                            ),
                          ),
                        if (trendSpots.isNotEmpty)
                          LineChartBarData(
                            spots: trendSpots,
                            isCurved: true,
                            color: AppColors.weight,
                            barWidth: 2.8,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.weight.withValues(alpha: 0.10),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TdeeChartCard extends StatelessWidget {
  const _TdeeChartCard({required this.points});

  final List<AnalyticsPointModel> points;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].estimatedTdeeKcal),
    ];
    final values = points.map((p) => p.estimatedTdeeKcal).toList();
    final minY = values.isEmpty ? 1500.0 : (values.reduce(math.min) - 150);
    final maxY = values.isEmpty ? 3000.0 : (values.reduce(math.max) + 150);

    return Container(
      decoration: AppTheme.matteCardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dépense énergétique adaptative (TDEE)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 185,
            child: spots.isEmpty
                ? const Center(child: Text('Données indisponibles'))
                : LineChart(
                    LineChartData(
                      minY: minY,
                      maxY: maxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => const FlLine(
                          color: AppColors.border,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: _buildDateTitles(points),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => AppColors.surfaceElevated,
                          getTooltipItems: (touched) => touched.map((s) {
                            final idx = s.x.toInt();
                            final d = idx >= 0 && idx < points.length
                                ? DateFormat('dd/MM').format(points[idx].date)
                                : '';
                            return LineTooltipItem(
                              '$d : ${s.y.round()} kcal',
                              AppTheme.numericStyle(
                                fontSize: 12,
                                color: AppColors.protein,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: AppColors.protein,
                          barWidth: 2.6,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.protein.withValues(alpha: 0.10),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _IntakeChartCard extends StatelessWidget {
  const _IntakeChartCard({
    required this.points,
    required this.calorieTarget,
  });

  final List<AnalyticsPointModel> points;
  final double calorieTarget;

  @override
  Widget build(BuildContext context) {
    final maxIntake = points.fold<double>(
      calorieTarget,
      (prev, p) => math.max(prev, p.intakeKcal),
    );

    return Container(
      decoration: AppTheme.matteCardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Apports caloriques vs Cible',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                maxY: maxIntake * 1.15,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.border,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: _buildDateTitles(points),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: calorieTarget,
                      color: AppColors.textSecondary,
                      strokeWidth: 1.5,
                      dashArray: [5, 5],
                    ),
                  ],
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.surfaceElevated,
                    getTooltipItem: (group, _, rod, __) {
                      final idx = group.x;
                      final d = idx >= 0 && idx < points.length
                          ? DateFormat('dd/MM').format(points[idx].date)
                          : '';
                      return BarTooltipItem(
                        '$d : ${rod.toY.round()} kcal',
                        AppTheme.numericStyle(
                          fontSize: 12,
                          color: AppColors.calories,
                        ),
                      );
                    },
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < points.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: points[i].intakeKcal,
                          color: AppColors.calories,
                          width: points.length > 35 ? 3 : 6,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

FlTitlesData _buildDateTitles(List<AnalyticsPointModel> points) {
  final step = math.max(1, (points.length / 4).floor());
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 42,
        getTitlesWidget: (val, _) => Text(
          val.round().toString(),
          style: AppTheme.numericStyle(
            fontSize: 10,
            color: AppColors.textMuted,
          ),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: step.toDouble(),
        getTitlesWidget: (val, _) {
          final idx = val.toInt();
          if (idx < 0 || idx >= points.length) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              DateFormat('dd/MM').format(points[idx].date),
              style: AppTheme.numericStyle(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
          );
        },
      ),
    ),
  );
}

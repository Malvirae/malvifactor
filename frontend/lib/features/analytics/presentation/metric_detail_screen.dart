import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/presentation/analytics_detail_screen.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';

enum MetricCategory {
  expenditure,
  goalProgress,
  weightTrend,
  bodyFat,
  weightHabits,
  foodHabits,
}

class MetricDetailScreen extends ConsumerStatefulWidget {
  const MetricDetailScreen({
    super.key,
    required this.category,
  });

  final MetricCategory category;

  @override
  ConsumerState<MetricDetailScreen> createState() => _MetricDetailScreenState();
}

class _MetricDetailScreenState extends ConsumerState<MetricDetailScreen> {
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  String get _title {
    switch (widget.category) {
      case MetricCategory.expenditure:
        return 'DÉPENSE (TDEE)';
      case MetricCategory.goalProgress:
        return 'PROGRESSION OBJECTIF';
      case MetricCategory.weightTrend:
        return 'POIDS TENDANCE';
      case MetricCategory.bodyFat:
        return 'MASSE GRASSE';
      case MetricCategory.weightHabits:
        return 'HABITUDES PESÉES';
      case MetricCategory.foodHabits:
        return 'HABITUDES JOURNAL';
    }
  }

  bool get _isHabitView =>
      widget.category == MetricCategory.weightHabits ||
      widget.category == MetricCategory.foodHabits;

  @override
  Widget build(BuildContext context) {
    final days = ref.watch(analyticsDaysProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _isHabitView
          ? _buildHabitCalendarView()
          : Column(
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
                        ref.read(analyticsDaysProvider.notifier).state =
                            sel.first,
                  ),
                ),
                Expanded(
                  child: _buildMetricBody(days),
                ),
              ],
            ),
    );
  }

  Widget _buildMetricBody(int days) {
    if (widget.category == MetricCategory.bodyFat) {
      final start = DateTime.now().subtract(Duration(days: days - 1));
      return FutureBuilder<List<WeightEntryModel>>(
        future: ref.read(dashboardRepositoryProvider).fetchWeights(
              startDate: start,
              endDate: DateTime.now(),
            ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.calories),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          final weights = (snapshot.data ?? const [])
              .where((w) => w.bodyFatPct != null)
              .toList();
          return _BodyFatDetailView(entries: weights);
        },
      );
    }

    final seriesAsync = ref.watch(analyticsSeriesProvider);
    return seriesAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.calories),
      ),
      error: (e, _) => Center(child: Text('Erreur : $e')),
      data: (points) {
        switch (widget.category) {
          case MetricCategory.expenditure:
            return _ExpenditureDetailView(points: points);
          case MetricCategory.goalProgress:
            return _GoalProgressDetailView(points: points);
          case MetricCategory.weightTrend:
            return _WeightTrendDetailView(points: points);
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _buildHabitCalendarView() {
    final monthStart = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final nextMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
    final monthEnd = nextMonth.subtract(const Duration(days: 1));
    final isWeight = widget.category == MetricCategory.weightHabits;
    final activeColor = isWeight ? AppColors.carbs : AppColors.calories;

    return FutureBuilder<Set<String>>(
      future: _loadMonthHabitKeys(monthStart, monthEnd, isWeight),
      builder: (context, snapshot) {
        final activeKeys = snapshot.data ?? const <String>{};
        final daysInMonth = monthEnd.day;
        final leadingBlanks = monthStart.weekday - 1; // Mon=1 -> 0
        final totalCells = leadingBlanks + daysInMonth;

        // Compute current streak up to today
        final streak = _computeStreak(activeKeys);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Container(
              decoration: AppTheme.matteCardDecoration(),
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Série en cours',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$streak jour${streak > 1 ? 's' : ''}',
                        style: AppTheme.numericStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: activeColor,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Ce mois-ci',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${activeKeys.length} / $daysInMonth j',
                        style: AppTheme.numericStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: AppTheme.matteCardDecoration(),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _focusedMonth = DateTime(
                              _focusedMonth.year,
                              _focusedMonth.month - 1,
                            );
                          });
                        },
                        icon: const Icon(LucideIcons.chevronLeft, size: 18),
                      ),
                      Text(
                        DateFormat('MMMM yyyy', 'fr_FR')
                            .format(monthStart)
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _focusedMonth = DateTime(
                              _focusedMonth.year,
                              _focusedMonth.month + 1,
                            );
                          });
                        },
                        icon: const Icon(LucideIcons.chevronRight, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _WeekdayHeader('L'),
                      _WeekdayHeader('M'),
                      _WeekdayHeader('M'),
                      _WeekdayHeader('J'),
                      _WeekdayHeader('V'),
                      _WeekdayHeader('S'),
                      _WeekdayHeader('D'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                        color: AppColors.calories,
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      itemCount: totalCells,
                      itemBuilder: (_, idx) {
                        if (idx < leadingBlanks) {
                          return const SizedBox.shrink();
                        }
                        final dayNum = idx - leadingBlanks + 1;
                        final dayDate = DateTime(
                          monthStart.year,
                          monthStart.month,
                          dayNum,
                        );
                        final key = _dateKey(dayDate);
                        final active = activeKeys.contains(key);
                        return Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active
                                ? activeColor.withValues(alpha: 0.22)
                                : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: active ? activeColor : AppColors.border,
                            ),
                          ),
                          child: Text(
                            '$dayNum',
                            style: AppTheme.numericStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: active
                                  ? activeColor
                                  : AppColors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Set<String>> _loadMonthHabitKeys(
    DateTime start,
    DateTime end,
    bool isWeight,
  ) async {
    final repo = ref.read(dashboardRepositoryProvider);
    if (isWeight) {
      final list = await repo.fetchWeights(startDate: start, endDate: end);
      return list.map((w) => _dateKey(w.measuredAt.toLocal())).toSet();
    } else {
      final list = await repo.fetchLogsSummary(start, end);
      return list
          .where((s) => s.entriesCount > 0)
          .map((s) => _dateKey(s.date))
          .toSet();
    }
  }

  int _computeStreak(Set<String> activeKeys) {
    var streak = 0;
    var cursor = DateTime.now();
    while (activeKeys.contains(_dateKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
      ),
    );
  }
}

class _EmptyChartState extends StatelessWidget {
  const _EmptyChartState();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 180,
      child: Center(
        child: Text(
          'Pas encore assez de données',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ),
    );
  }
}

class _ExpenditureDetailView extends StatelessWidget {
  const _ExpenditureDetailView({required this.points});

  final List<AnalyticsPointModel> points;

  @override
  Widget build(BuildContext context) {
    final hasEnough = points.length >= 2;
    final first = points.isNotEmpty ? points.first.estimatedTdeeKcal : 0.0;
    final last = points.isNotEmpty ? points.last.estimatedTdeeKcal : 0.0;
    final delta = last - first;

    final validPoints = [
      for (var i = 0; i < points.length; i++)
        if (points[i].estimatedTdeeKcal > 0)
          FlSpot(i.toDouble(), points[i].estimatedTdeeKcal),
    ];
    final values = points
        .map((p) => p.estimatedTdeeKcal)
        .where((v) => v > 0)
        .toList();
    final minY = values.isEmpty
        ? 1500.0
        : math.max(0.0, values.reduce(math.min) - 150);
    final maxY = values.isEmpty ? 3000.0 : values.reduce(math.max) + 150;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        Container(
          decoration: AppTheme.matteCardDecoration(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${last.round()} kcal / j',
                    style: AppTheme.numericStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.protein,
                    ),
                  ),
                  Text(
                    '${delta >= 0 ? '+' : ''}${delta.round()} kcal sur la période',
                    style: AppTheme.numericStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!hasEnough)
                const _EmptyChartState()
              else
                SizedBox(
                  height: 220,
                  child: LineChart(
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
                      titlesData: _buildMetricDateTitles(points),
                      lineBarsData: [
                        LineChartBarData(
                          spots: validPoints,
                          isCurved: true,
                          curveSmoothness: 0.15,
                          preventCurveOverShooting: true,
                          color: AppColors.protein,
                          barWidth: 2.8,
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
        ),
        const SizedBox(height: 14),
        Container(
          decoration: AppTheme.matteCardDecoration(),
          padding: const EdgeInsets.all(16),
          child: const Text(
            'Le TDEE adaptatif est recalculé sur une fenêtre glissante de 21 jours à partir de vos apports moyens (hors jours incomplets < 40 % du TDEE) et de la variation de votre poids tendance lissé (EWMA).',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _GoalProgressDetailView extends StatelessWidget {
  const _GoalProgressDetailView({required this.points});

  final List<AnalyticsPointModel> points;

  @override
  Widget build(BuildContext context) {
    final logged = points.where((p) => p.intakeKcal > 0).toList();
    final adherence = logged.isEmpty
        ? 0.0
        : (logged
                    .map((p) => p.targetKcal <= 0
                        ? 0.0
                        : (1.0 -
                                ((p.intakeKcal - p.targetKcal).abs() /
                                    p.targetKcal))
                            .clamp(0.0, 1.0))
                    .reduce((a, b) => a + b) /
                logged.length) *
            100.0;

    final maxY = points.fold<double>(
      1000.0,
      (prev, p) => math.max(prev, math.max(p.intakeKcal, p.targetKcal)),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        Container(
          decoration: AppTheme.matteCardDecoration(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Adhérence : ${adherence.round()} %',
                    style: AppTheme.numericStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.carbs,
                    ),
                  ),
                  Text(
                    '${logged.length} jours saisis',
                    style: AppTheme.numericStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (logged.isEmpty)
                const _EmptyChartState()
              else
                SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      maxY: maxY * 1.15,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => const FlLine(
                          color: AppColors.border,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: _buildMetricDateTitles(points),
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
        ),
      ],
    );
  }
}

class _WeightTrendDetailView extends StatelessWidget {
  const _WeightTrendDetailView({required this.points});

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

    final hasEnough = trendSpots.length >= 2 || rawSpots.length >= 2;
    final minY = values.isEmpty ? 60.0 : values.reduce(math.min) - 1.5;
    final maxY = values.isEmpty ? 90.0 : values.reduce(math.max) + 1.5;

    final startTrend = trendSpots.isNotEmpty ? trendSpots.first.y : null;
    final endTrend = trendSpots.isNotEmpty ? trendSpots.last.y : null;
    final delta = (startTrend != null && endTrend != null)
        ? endTrend - startTrend
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        Container(
          decoration: AppTheme.matteCardDecoration(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    endTrend != null
                        ? '${endTrend.toStringAsFixed(1)} kg'
                        : '-- kg',
                    style: AppTheme.numericStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.weight,
                    ),
                  ),
                  if (delta != null)
                    Text(
                      '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)} kg',
                      style: AppTheme.numericStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (!hasEnough)
                const _EmptyChartState()
              else
                SizedBox(
                  height: 220,
                  child: LineChart(
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
                      titlesData: _buildMetricDateTitles(points),
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
                            curveSmoothness: 0.15,
                            preventCurveOverShooting: true,
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
        ),
      ],
    );
  }
}

class _BodyFatDetailView extends StatelessWidget {
  const _BodyFatDetailView({required this.entries});

  final List<WeightEntryModel> entries;

  @override
  Widget build(BuildContext context) {
    final hasEnough = entries.length >= 2;
    final values = entries.map((e) => e.bodyFatPct!).toList();
    final minY = values.isEmpty ? 5.0 : values.reduce(math.min) - 1.5;
    final maxY = values.isEmpty ? 35.0 : values.reduce(math.max) + 1.5;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        Container(
          decoration: AppTheme.matteCardDecoration(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entries.isNotEmpty
                    ? '${entries.last.bodyFatPct!.toStringAsFixed(1)} %'
                    : '-- %',
                style: AppTheme.numericStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.weight,
                ),
              ),
              const SizedBox(height: 16),
              if (!hasEnough)
                const _EmptyChartState()
              else
                SizedBox(
                  height: 220,
                  child: LineChart(
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
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < entries.length; i++)
                              FlSpot(i.toDouble(), entries[i].bodyFatPct!),
                          ],
                          isCurved: true,
                          color: AppColors.weight,
                          barWidth: 2.8,
                          dotData: const FlDotData(show: true),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

FlTitlesData _buildMetricDateTitles(List<AnalyticsPointModel> points) {
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
        getTitlesWidget: (val, meta) {
          final idx = val.toInt();
          if (idx < 0 || idx >= points.length) {
            return const SizedBox.shrink();
          }
          if (val != meta.max &&
              (meta.max - val) < meta.appliedInterval * 0.65) {
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

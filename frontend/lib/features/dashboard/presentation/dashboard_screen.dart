import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/presentation/analytics_detail_screen.dart';
import 'package:malvifactor/features/analytics/presentation/metric_detail_screen.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/shared/widgets/macro_rings_card.dart';
import 'package:malvifactor/shared/widgets/weight_entry_dialog.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _openAnalytics(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AnalyticsDetailScreen()),
    );
  }

  void _openMetric(BuildContext context, MetricCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MetricDetailScreen(category: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'DASHBOARD',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Ajouter une pesée',
            onPressed: () => showManualWeightDialog(context, ref),
            icon: const Icon(LucideIcons.scale, size: 20),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.calories,
        backgroundColor: AppColors.surface,
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: dashboardAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.calories),
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                decoration: AppTheme.matteCardDecoration(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(
                      LucideIcons.cloudOff,
                      color: AppColors.error,
                      size: 36,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Impossible de charger le tableau de bord',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(dashboardProvider),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          data: (data) => _DashboardBody(
            data: data,
            onOpenAnalytics: () => _openAnalytics(context),
            onOpenMetric: (cat) => _openMetric(context, cat),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.data,
    required this.onOpenAnalytics,
    required this.onOpenMetric,
  });

  final DashboardData data;
  final VoidCallback onOpenAnalytics;
  final ValueChanged<MetricCategory> onOpenMetric;

  @override
  Widget build(BuildContext context) {
    final last7Analytics = data.analytics.length > 7
        ? data.analytics.sublist(data.analytics.length - 7)
        : data.analytics;

    final tdeeSpots = [
      for (var i = 0; i < last7Analytics.length; i++)
        FlSpot(i.toDouble(), last7Analytics[i].estimatedTdeeKcal),
    ];

    final weightSpots = <FlSpot>[];
    for (var i = 0; i < last7Analytics.length; i++) {
      final trend = last7Analytics[i].trendWeightKg;
      if (trend != null) {
        weightSpots.add(FlSpot(i.toDouble(), trend));
      }
    }

    final logged7 = last7Analytics.where((p) => p.intakeKcal > 0).toList();
    final adherencePct = logged7.isEmpty
        ? 0.0
        : (logged7
                    .map((p) {
                      final denom = p.targetKcal > 0
                          ? p.targetKcal
                          : data.profile.currentCalorieTarget;
                      if (denom <= 0) return 0.0;
                      return (1.0 - ((p.intakeKcal - denom).abs() / denom))
                          .clamp(0.0, 1.0);
                    })
                    .reduce((a, b) => a + b) /
                logged7.length) *
            100.0;

    final latestWeight = data.latestWeight;
    final latestTrend = latestWeight != null
        ? (latestWeight.trendWeightKg ?? latestWeight.weightKg)
        : null;

    final fatEntries = data.weights
        .where((w) => w.bodyFatPct != null)
        .toList();
    final hasFat = fatEntries.isNotEmpty;
    final fatOrRawTitle = hasFat ? 'Masse grasse' : 'Poids brut';
    final fatOrRawValue = hasFat
        ? '${fatEntries.last.bodyFatPct!.toStringAsFixed(1)} %'
        : (latestWeight != null
            ? '${latestWeight.weightKg.toStringAsFixed(1)} kg'
            : '--');

    String fatOrRawDelta = 'Dernière mesure';
    if (hasFat && fatEntries.length >= 2) {
      final delta =
          fatEntries.last.bodyFatPct! - fatEntries[fatEntries.length - 2].bodyFatPct!;
      fatOrRawDelta = '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} %';
    } else if (!hasFat && data.weights.length >= 2) {
      final delta = data.weights.last.weightKg -
          data.weights[data.weights.length - 2].weightKg;
      fatOrRawDelta = '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg';
    }

    final today = DateTime.now();
    final weightDaysSet = data.weights
        .map((w) => _dateKey(w.measuredAt.toLocal()))
        .toSet();
    final logDaysSet = data.logsSummary
        .where((s) => s.entriesCount > 0)
        .map((s) => _dateKey(s.date))
        .toSet();

    final last30Keys = List.generate(
      30,
      (i) => _dateKey(today.subtract(Duration(days: 29 - i))),
    );
    final last7Keys = last30Keys.sublist(23);
    final weightThisWeek = last7Keys.where(weightDaysSet.contains).length;
    final logsThisWeek = last7Keys.where(logDaysSet.contains).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        MacroRingsCard(
          totals: data.dayLogs.totals,
          targets: data.dayLogs.targets,
          remaining: data.dayLogs.remaining,
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Insights & Analyses',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            InkWell(
              onTap: onOpenAnalytics,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    Text(
                      'Tout voir',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InsightSparkCard(
                title: 'Dépense (TDEE)',
                subtitle: '7 derniers jours',
                value: '${data.profile.currentTdeeKcal.round()} kcal',
                color: AppColors.protein,
                spots: tdeeSpots,
                onTap: () => onOpenMetric(MetricCategory.expenditure),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AdherenceInsightCard(
                adherencePct: adherencePct,
                onTap: () => onOpenMetric(MetricCategory.goalProgress),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InsightSparkCard(
                title: 'Poids tendance',
                subtitle: '7 derniers jours',
                value: latestTrend != null
                    ? '${latestTrend.toStringAsFixed(1)} kg'
                    : '-- kg',
                color: AppColors.weight,
                spots: weightSpots,
                onTap: () => onOpenMetric(MetricCategory.weightTrend),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SimpleInsightCard(
                title: fatOrRawTitle,
                subtitle: fatOrRawDelta,
                value: fatOrRawValue,
                color: AppColors.weight,
                onTap: () => onOpenMetric(
                  hasFat
                      ? MetricCategory.bodyFat
                      : MetricCategory.weightTrend,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Habitudes',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _HabitHeatmapCard(
                title: 'Pesées',
                subtitle: '30 derniers jours',
                keys: last30Keys,
                activeKeys: weightDaysSet,
                activeColor: AppColors.carbs,
                weekCount: weightThisWeek,
                onTap: () => onOpenMetric(MetricCategory.weightHabits),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HabitHeatmapCard(
                title: 'Journal alimentaire',
                subtitle: '30 derniers jours',
                keys: last30Keys,
                activeKeys: logDaysSet,
                activeColor: AppColors.calories,
                weekCount: logsThisWeek,
                onTap: () => onOpenMetric(MetricCategory.foodHabits),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _InsightSparkCard extends StatelessWidget {
  const _InsightSparkCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.spots,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String value;
  final Color color;
  final List<FlSpot> spots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ys = spots.map((s) => s.y).toList();
    final minY = ys.isEmpty ? 0.0 : ys.reduce(math.min) - 1;
    final maxY = ys.isEmpty ? 10.0 : ys.reduce(math.max) + 1;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: AppTheme.matteCardDecoration(),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: spots.length < 2
                  ? const Center(
                      child: Text(
                        'Pas encore assez de données',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minY: minY,
                        maxY: maxY,
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: false,
                            color: color,
                            barWidth: 2.2,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (_, __, ___, ____) =>
                                  FlDotCirclePainter(
                                radius: 2.8,
                                color: AppColors.surface,
                                strokeWidth: 1.8,
                                strokeColor: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  style: AppTheme.numericStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdherenceInsightCard extends StatelessWidget {
  const _AdherenceInsightCard({
    required this.adherencePct,
    required this.onTap,
  });

  final double adherencePct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = (adherencePct / 100.0).clamp(0.0, 1.0);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: AppTheme.matteCardDecoration(),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Progression objectif',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const Text(
              '7 derniers jours',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: AppColors.surfaceElevated,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.carbs),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${adherencePct.round()} %',
                  style: AppTheme.numericStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleInsightCard extends StatelessWidget {
  const _SimpleInsightCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: AppTheme.matteCardDecoration(),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 46),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  style: AppTheme.numericStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitHeatmapCard extends StatelessWidget {
  const _HabitHeatmapCard({
    required this.title,
    required this.subtitle,
    required this.keys,
    required this.activeKeys,
    required this.activeColor,
    required this.weekCount,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<String> keys;
  final Set<String> activeKeys;
  final Color activeColor;
  final int weekCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: AppTheme.matteCardDecoration(),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 10,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: keys.length,
              itemBuilder: (_, idx) {
                final active = activeKeys.contains(keys[idx]);
                return Container(
                  decoration: BoxDecoration(
                    color: active ? activeColor : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$weekCount/7 cette semaine',
                  style: AppTheme.numericStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

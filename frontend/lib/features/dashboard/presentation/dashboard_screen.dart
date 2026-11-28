import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/core/widgets/pressable_scale.dart';
import 'package:malvifactor/features/analytics/presentation/metric_detail_screen.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';
import 'package:malvifactor/features/dashboard/presentation/widgets/weekly_nutrition_card.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/shared/widgets/habit_day_detail_sheet.dart';
import 'package:malvifactor/shared/widgets/macro_rings_card.dart';
import 'package:malvifactor/shared/widgets/weight_entry_dialog.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

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
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: const [
              SkeletonPulseBox(height: 280, borderRadius: 18),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: SkeletonPulseBox(height: 142, borderRadius: 16)),
                  SizedBox(width: 10),
                  Expanded(child: SkeletonPulseBox(height: 142, borderRadius: 16)),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: SkeletonPulseBox(height: 142, borderRadius: 16)),
                  SizedBox(width: 10),
                  Expanded(child: SkeletonPulseBox(height: 142, borderRadius: 16)),
                ],
              ),
            ],
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
    required this.onOpenMetric,
  });

  final DashboardData data;
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
        ? '${fatEntries.last.bodyFatPct!.toStringAsFixed(1).replaceAll('.', ',')} %'
        : (latestWeight != null
            ? '${latestWeight.weightKg.toStringAsFixed(1).replaceAll('.', ',')} kg'
            : '--');

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final last7Start = todayDate.subtract(const Duration(days: 6));

    final fatOrRawSpots = <FlSpot>[];
    if (hasFat) {
      final fatByDay = <int, double>{};
      for (final w in fatEntries) {
        final d = w.measuredAt.toLocal();
        final dayOnly = DateTime(d.year, d.month, d.day);
        final idx = dayOnly.difference(last7Start).inDays;
        if (idx >= 0 && idx < 7 && w.bodyFatPct != null) {
          fatByDay[idx] = w.bodyFatPct!;
        }
      }
      final sorted = fatByDay.keys.toList()..sort();
      for (final i in sorted) {
        fatOrRawSpots.add(FlSpot(i.toDouble(), fatByDay[i]!));
      }
    } else {
      final rawByDay = <int, double>{};
      for (final w in data.weights) {
        final d = w.measuredAt.toLocal();
        final dayOnly = DateTime(d.year, d.month, d.day);
        final idx = dayOnly.difference(last7Start).inDays;
        if (idx >= 0 && idx < 7) {
          rawByDay[idx] = w.weightKg;
        }
      }
      final sorted = rawByDay.keys.toList()..sort();
      for (final i in sorted) {
        fatOrRawSpots.add(FlSpot(i.toDouble(), rawByDay[i]!));
      }
    }
    final weightByKey = <String, WeightEntryModel>{};
    for (final w in data.weights) {
      weightByKey[_dateKey(w.measuredAt.toLocal())] = w;
    }
    final weightDaysSet = weightByKey.keys.toSet();

    final logSummaryByKey = <String, DaySummaryModel>{};
    for (final s in data.logsSummary) {
      if (s.entriesCount > 0) {
        logSummaryByKey[_dateKey(s.date)] = s;
      }
    }
    final logDaysSet = logSummaryByKey.keys.toSet();

    final last30Dates = List.generate(
      30,
      (i) => todayDate.subtract(Duration(days: 29 - i)),
    );
    final last30Keys = last30Dates.map(_dateKey).toList();
    final last7Keys = last30Keys.sublist(23);
    final weightThisWeek = last7Keys.where(weightDaysSet.contains).length;
    final logsThisWeek = last7Keys.where(logDaysSet.contains).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
      children: [
        SoftFadeIn(
          child: _NutritionCarousel(
            dayLogs: data.dayLogs,
            weeklyNutrition: data.weeklyNutrition,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 14),
              const Text(
                'Insights & Analyses',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              SoftFadeIn(
                delayMs: 40,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _InsightSparkCard(
                          title: 'Dépense (TDEE)',
                          subtitle: '7 derniers jours',
                          value: '${data.profile.currentTdeeKcal.round()} kcal',
                          color: AppColors.expenditure,
                          spots: tdeeSpots,
                          onTap: () => onOpenMetric(MetricCategory.expenditure),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AdherenceInsightCard(
                          adherencePct: adherencePct,
                          onTap: () =>
                              onOpenMetric(MetricCategory.goalProgress),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SoftFadeIn(
                delayMs: 80,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _InsightSparkCard(
                          title: 'Tendance de poids',
                          subtitle: '7 derniers jours',
                          value: latestTrend != null
                              ? '${latestTrend.toStringAsFixed(1).replaceAll('.', ',')} kg'
                              : '-- kg',
                          color: AppColors.weight,
                          spots: weightSpots,
                          onTap: () =>
                              onOpenMetric(MetricCategory.weightTrend),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _InsightSparkCard(
                          title: fatOrRawTitle,
                          subtitle: '7 derniers jours',
                          value: fatOrRawValue,
                          color: AppColors.bodyFat,
                          spots: fatOrRawSpots,
                          onTap: () => onOpenMetric(
                            hasFat
                                ? MetricCategory.bodyFat
                                : MetricCategory.weightTrend,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                      onCellTap: (idx) {
                        final key = last30Keys[idx];
                        final entry = weightByKey[key];
                        if (entry != null) {
                          showWeightHabitDetailSheet(
                            context,
                            date: last30Dates[idx],
                            entry: entry,
                          );
                        }
                      },
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
                      onCellTap: (idx) {
                        final key = last30Keys[idx];
                        final summary = logSummaryByKey[key];
                        if (summary != null) {
                          showFoodHabitDetailSheet(
                            context,
                            date: last30Dates[idx],
                            summary: summary,
                            targets: data.dayLogs.targets,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _NutritionCarousel extends StatefulWidget {
  const _NutritionCarousel({
    required this.dayLogs,
    required this.weeklyNutrition,
  });

  final DayLogsModel dayLogs;
  final WeeklyNutritionModel weeklyNutrition;

  @override
  State<_NutritionCarousel> createState() => _NutritionCarouselState();
}

class _NutritionCarouselState extends State<_NutritionCarousel> {
  static const double _cardHeight = 352.0;

  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    if (_currentPage == index) return;
    HapticFeedback.selectionClick();
    _pageController.animateToPage(
      index,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _cardHeight,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: PageView(
              controller: _pageController,
              onPageChanged: (idx) {
                if (_currentPage != idx) {
                  setState(() => _currentPage = idx);
                }
              },
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: MacroRingsCard(
                    totals: widget.dayLogs.totals,
                    targets: widget.dayLogs.targets,
                    remaining: widget.dayLogs.remaining,
                    fillHeight: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: WeeklyNutritionCard(
                    weekly: widget.weeklyNutrition,
                    fillHeight: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 2; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _goToPage(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 6,
                  ),
                  child: AnimatedContainer(
                    duration: disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: _currentPage == i ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _currentPage == i
                          ? const Color(0xFFF8FAFC)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
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

    return PressableScale(
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
                  : RepaintBoundary(
                      child: LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: 6,
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
    return PressableScale(
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
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: Center(
                child: AnimatedMacroBar(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: AppColors.surfaceElevated,
                  color: AppColors.carbs,
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

class _HabitHeatmapCard extends StatelessWidget {
  const _HabitHeatmapCard({
    required this.title,
    required this.subtitle,
    required this.keys,
    required this.activeKeys,
    required this.activeColor,
    required this.weekCount,
    required this.onTap,
    required this.onCellTap,
  });

  final String title;
  final String subtitle;
  final List<String> keys;
  final Set<String> activeKeys;
  final Color activeColor;
  final int weekCount;
  final VoidCallback onTap;
  final ValueChanged<int> onCellTap;

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
                final cell = Container(
                  decoration: BoxDecoration(
                    color: active ? activeColor : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
                if (!active) return cell;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onCellTap(idx),
                  child: cell,
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

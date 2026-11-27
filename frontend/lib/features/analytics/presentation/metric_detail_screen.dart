import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/presentation/widgets/body_fat_view.dart';
import 'package:malvifactor/features/analytics/presentation/widgets/expenditure_view.dart';
import 'package:malvifactor/features/analytics/presentation/widgets/goal_progress_view.dart';
import 'package:malvifactor/features/analytics/presentation/widgets/weight_trend_view.dart';
import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';
import 'package:malvifactor/features/profile/providers/profile_provider.dart';
import 'package:malvifactor/shared/widgets/habit_day_detail_sheet.dart';

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
        return 'PROGRESSION DE L’OBJECTIF';
      case MetricCategory.weightTrend:
        return 'TENDANCE DE POIDS';
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
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _isHabitView ? _buildHabitCalendarView() : _buildFullMetricView(),
    );
  }

  Widget _buildFullMetricView() {
    final ctxAsync = ref.watch(fullMetricContextProvider);
    return ctxAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.calories),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Erreur : $e', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(fullMetricContextProvider),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
      data: (ctx) {
        switch (widget.category) {
          case MetricCategory.weightTrend:
            return WeightTrendDetailView(ctx: ctx);
          case MetricCategory.expenditure:
            return ExpenditureDetailView(ctx: ctx);
          case MetricCategory.goalProgress:
            return GoalProgressDetailView(ctx: ctx);
          case MetricCategory.bodyFat:
            return BodyFatDetailView(ctx: ctx);
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
    final profile = ref.watch(profileProvider).valueOrNull;
    final targets = profile == null
        ? null
        : MacroSummaryModel(
            kcal: profile.currentCalorieTarget,
            proteinG: profile.currentProteinG,
            fatG: profile.currentFatG,
            carbsG: profile.currentCarbsG,
          );

    return FutureBuilder<_HabitMonthData>(
      future: _loadMonthHabitData(monthStart, monthEnd, isWeight),
      builder: (context, snapshot) {
        final monthData = snapshot.data ?? const _HabitMonthData();
        final activeKeys = monthData.activeKeys;
        final daysInMonth = monthEnd.day;
        final leadingBlanks = monthStart.weekday - 1; // Mon=1 -> 0
        final totalCells = leadingBlanks + daysInMonth;

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
                        final cell = Container(
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
                        if (!active) return cell;
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            if (isWeight) {
                              final entry = monthData.weightsByKey[key];
                              if (entry != null) {
                                showWeightHabitDetailSheet(
                                  context,
                                  date: dayDate,
                                  entry: entry,
                                );
                              }
                            } else {
                              final summary = monthData.summariesByKey[key];
                              if (summary != null) {
                                showFoodHabitDetailSheet(
                                  context,
                                  date: dayDate,
                                  summary: summary,
                                  targets: targets,
                                );
                              }
                            }
                          },
                          child: cell,
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

  Future<_HabitMonthData> _loadMonthHabitData(
    DateTime start,
    DateTime end,
    bool isWeight,
  ) async {
    final repo = ref.read(dashboardRepositoryProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final boundedEnd = end.isAfter(today) ? today : end;
    if (boundedEnd.isBefore(start)) {
      return const _HabitMonthData();
    }

    if (isWeight) {
      final list =
          await repo.fetchWeights(startDate: start, endDate: boundedEnd);
      final weightsByKey = <String, WeightEntryModel>{};
      for (final w in list) {
        weightsByKey[_dateKey(w.measuredAt.toLocal())] = w;
      }
      return _HabitMonthData(
        activeKeys: weightsByKey.keys.toSet(),
        weightsByKey: weightsByKey,
      );
    } else {
      final list = await repo.fetchLogsSummary(start, boundedEnd);
      final summariesByKey = <String, DaySummaryModel>{};
      for (final s in list) {
        if (s.entriesCount > 0) {
          summariesByKey[_dateKey(s.date)] = s;
        }
      }
      return _HabitMonthData(
        activeKeys: summariesByKey.keys.toSet(),
        summariesByKey: summariesByKey,
      );
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

class _HabitMonthData {
  const _HabitMonthData({
    this.activeKeys = const {},
    this.weightsByKey = const {},
    this.summariesByKey = const {},
  });

  final Set<String> activeKeys;
  final Map<String, WeightEntryModel> weightsByKey;
  final Map<String, DaySummaryModel> summariesByKey;
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

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';
import 'package:malvifactor/features/profile/data/profile_repository.dart';

class DashboardData {
  const DashboardData({
    required this.dayLogs,
    required this.profile,
    required this.weights,
    required this.analytics,
    required this.logsSummary,
    required this.weeklyNutrition,
  });

  final DayLogsModel dayLogs;
  final UserProfileModel profile;
  final List<WeightEntryModel> weights;
  final List<AnalyticsPointModel> analytics;
  final List<DaySummaryModel> logsSummary;
  final WeeklyNutritionModel weeklyNutrition;

  WeightEntryModel? get latestWeight => weights.isNotEmpty ? weights.last : null;
}

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  final dashRepo = ref.watch(dashboardRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);
  final today = DateTime.now();
  final thirtyDaysAgo = today.subtract(const Duration(days: 29));

  Future<WeeklyNutritionModel?> safeFetchWeekly() async {
    try {
      return await dashRepo.fetchWeeklyNutrition(referenceDate: today);
    } on DioException {
      return null;
    }
  }

  final results = await Future.wait<dynamic>([
    dashRepo.fetchDayLogs(today),
    profileRepo.fetchProfile(),
    dashRepo.fetchWeights(startDate: thirtyDaysAgo, endDate: today),
    dashRepo.fetchAnalytics(30),
    dashRepo.fetchLogsSummary(thirtyDaysAgo, today),
    safeFetchWeekly(),
  ]);

  final dayLogs = results[0] as DayLogsModel;
  final profile = results[1] as UserProfileModel;
  final weights = results[2] as List<WeightEntryModel>;
  final analytics = results[3] as List<AnalyticsPointModel>;
  final logsSummary = results[4] as List<DaySummaryModel>;
  final weeklyNutrition = (results[5] as WeeklyNutritionModel?) ??
      WeeklyNutritionModel.fallback(
        today: today,
        summary: logsSummary,
        defaultTargets: dayLogs.targets,
      );

  return DashboardData(
    dayLogs: dayLogs,
    profile: profile,
    weights: weights,
    analytics: analytics,
    logsSummary: logsSummary,
    weeklyNutrition: weeklyNutrition,
  );
});

final weeklyNutritionProvider = Provider<AsyncValue<WeeklyNutritionModel>>(
  (ref) => ref.watch(dashboardProvider).whenData((d) => d.weeklyNutrition),
);

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
  });

  final DayLogsModel dayLogs;
  final UserProfileModel profile;
  final List<WeightEntryModel> weights;
  final List<AnalyticsPointModel> analytics;
  final List<DaySummaryModel> logsSummary;

  WeightEntryModel? get latestWeight => weights.isNotEmpty ? weights.last : null;
}

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  final dashRepo = ref.watch(dashboardRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);
  final today = DateTime.now();
  final thirtyDaysAgo = today.subtract(const Duration(days: 29));

  final results = await Future.wait<dynamic>([
    dashRepo.fetchDayLogs(today),
    profileRepo.fetchProfile(),
    dashRepo.fetchWeights(startDate: thirtyDaysAgo, endDate: today),
    dashRepo.fetchAnalytics(30),
    dashRepo.fetchLogsSummary(thirtyDaysAgo, today),
  ]);

  return DashboardData(
    dayLogs: results[0] as DayLogsModel,
    profile: results[1] as UserProfileModel,
    weights: results[2] as List<WeightEntryModel>,
    analytics: results[3] as List<AnalyticsPointModel>,
    logsSummary: results[4] as List<DaySummaryModel>,
  );
});

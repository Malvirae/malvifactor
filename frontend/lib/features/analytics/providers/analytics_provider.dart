import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';
import 'package:malvifactor/features/profile/data/profile_repository.dart';
import 'package:malvifactor/features/profile/providers/profile_provider.dart';

class FullMetricContext {
  const FullMetricContext({
    required this.points,
    required this.allWeights,
    required this.profile,
    required this.preview,
  });

  final List<AnalyticsPointModel> points;
  final List<WeightEntryModel> allWeights;
  final UserProfileModel profile;
  final CheckinPreviewModel preview;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final fullMetricContextProvider = FutureProvider<FullMetricContext>((ref) async {
  final dashRepo = ref.watch(dashboardRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);

  final results = await Future.wait<dynamic>([
    dashRepo.fetchFullAnalytics(),
    dashRepo.fetchWeights(),
    profileRepo.fetchProfile(),
    dashRepo.fetchCheckinPreview(),
  ]);

  final today = _dateOnly(DateTime.now());
  final rawPoints = (results[0] as List<AnalyticsPointModel>)
      .where((p) => !_dateOnly(p.date).isAfter(today))
      .toList();
  final allWeights = (results[1] as List<WeightEntryModel>)
      .where((w) => !_dateOnly(w.measuredAt.toLocal()).isAfter(today))
      .toList();
  final profile = results[2] as UserProfileModel;
  final preview = results[3] as CheckinPreviewModel;

  // Ensure the timeline covers the earliest weigh-in even if backend caps analytics at 365 days.
  final mergedPoints = _mergeWithEarlierWeights(
    rawPoints: rawPoints,
    allWeights: allWeights,
    fallbackTdee: profile.initialTdeeKcal > 0
        ? profile.initialTdeeKcal
        : profile.currentTdeeKcal,
    fallbackTarget: profile.currentCalorieTarget,
  );

  // Also ensure profileProvider stays warm.
  ref.watch(profileProvider);

  return FullMetricContext(
    points: mergedPoints,
    allWeights: allWeights,
    profile: profile,
    preview: preview,
  );
});

List<AnalyticsPointModel> _mergeWithEarlierWeights({
  required List<AnalyticsPointModel> rawPoints,
  required List<WeightEntryModel> allWeights,
  required double fallbackTdee,
  required double fallbackTarget,
}) {
  if (allWeights.isEmpty) return rawPoints;

  final weightByDay = <String, WeightEntryModel>{};
  DateTime earliestWeight = _dateOnly(allWeights.first.measuredAt.toLocal());
  for (final w in allWeights) {
    final local = _dateOnly(w.measuredAt.toLocal());
    if (local.isBefore(earliestWeight)) earliestWeight = local;
    weightByDay[_dateKey(local)] = w;
  }

  if (rawPoints.isEmpty) {
    final today = _dateOnly(DateTime.now());
    final count = today.difference(earliestWeight).inDays + 1;
    return List.generate(count < 7 ? 7 : count, (i) {
      final d = today.subtract(Duration(days: (count < 7 ? 7 : count) - 1 - i));
      final w = weightByDay[_dateKey(d)];
      return AnalyticsPointModel(
        date: d,
        intakeKcal: 0,
        targetKcal: fallbackTarget,
        weightKg: w?.weightKg,
        trendWeightKg: w?.trendWeightKg,
        estimatedTdeeKcal: fallbackTdee,
      );
    });
  }

  final firstAnalyticsDay = _dateOnly(rawPoints.first.date);
  if (!earliestWeight.isBefore(firstAnalyticsDay)) {
    return rawPoints;
  }

  final extraDays = firstAnalyticsDay.difference(earliestWeight).inDays;
  final prefix = List.generate(extraDays, (i) {
    final d = earliestWeight.add(Duration(days: i));
    final w = weightByDay[_dateKey(d)];
    return AnalyticsPointModel(
      date: d,
      intakeKcal: 0,
      targetKcal: fallbackTarget,
      weightKg: w?.weightKg,
      trendWeightKg: w?.trendWeightKg,
      estimatedTdeeKcal: rawPoints.first.estimatedTdeeKcal > 0
          ? rawPoints.first.estimatedTdeeKcal
          : fallbackTdee,
    );
  });

  return [...prefix, ...rawPoints];
}

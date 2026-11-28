import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:malvifactor/core/network/dio_client.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';

class WeeklyCheckinModel {
  const WeeklyCheckinModel({
    required this.id,
    required this.checkinDate,
    required this.periodStart,
    required this.periodEnd,
    required this.avgIntakeKcal,
    required this.daysLoggedCount,
    required this.startTrendWeightKg,
    required this.endTrendWeightKg,
    required this.calculatedTdeeKcal,
    required this.newCalorieTarget,
    required this.newProteinG,
    required this.newFatG,
    required this.newCarbsG,
    required this.accepted,
  });

  final String id;
  final DateTime checkinDate;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double avgIntakeKcal;
  final int daysLoggedCount;
  final double startTrendWeightKg;
  final double endTrendWeightKg;
  final double calculatedTdeeKcal;
  final double newCalorieTarget;
  final double newProteinG;
  final double newFatG;
  final double newCarbsG;
  final bool accepted;

  factory WeeklyCheckinModel.fromJson(Map<String, dynamic> json) {
    return WeeklyCheckinModel(
      id: json['id'] as String,
      checkinDate: DateTime.parse(json['checkin_date'] as String),
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      avgIntakeKcal: (json['avg_intake_kcal'] as num).toDouble(),
      daysLoggedCount: (json['days_logged_count'] as num).toInt(),
      startTrendWeightKg: (json['start_trend_weight_kg'] as num).toDouble(),
      endTrendWeightKg: (json['end_trend_weight_kg'] as num).toDouble(),
      calculatedTdeeKcal: (json['calculated_tdee_kcal'] as num).toDouble(),
      newCalorieTarget: (json['new_calorie_target'] as num).toDouble(),
      newProteinG: (json['new_protein_g'] as num).toDouble(),
      newFatG: (json['new_fat_g'] as num).toDouble(),
      newCarbsG: (json['new_carbs_g'] as num).toDouble(),
      accepted: json['accepted'] as bool,
    );
  }
}

class StrategyRepository {
  StrategyRepository(this._dio);

  final Dio _dio;

  Future<CheckinPreviewModel> fetchPreview() async {
    final res =
        await _dio.get<Map<String, dynamic>>('/api/v1/checkins/preview');
    return CheckinPreviewModel.fromJson(res.data!);
  }

  Future<WeeklyCheckinModel> acceptCheckin() async {
    final res =
        await _dio.post<Map<String, dynamic>>('/api/v1/checkins/accept');
    return WeeklyCheckinModel.fromJson(res.data!);
  }

  Future<List<WeeklyCheckinModel>> listCheckins() async {
    final res = await _dio.get<List<dynamic>>('/api/v1/checkins');
    return (res.data ?? const [])
        .map((e) => WeeklyCheckinModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final strategyRepositoryProvider = Provider<StrategyRepository>(
  (ref) => StrategyRepository(ref.watch(dioProvider)),
);

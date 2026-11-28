import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:malvifactor/core/network/dio_client.dart';

class MacroSummaryModel {
  const MacroSummaryModel({
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  final double kcal;
  final double proteinG;
  final double fatG;
  final double carbsG;

  factory MacroSummaryModel.fromJson(Map<String, dynamic> json) {
    return MacroSummaryModel(
      kcal: (json['kcal'] as num).toDouble(),
      proteinG: (json['protein_g'] as num).toDouble(),
      fatG: (json['fat_g'] as num).toDouble(),
      carbsG: (json['carbs_g'] as num).toDouble(),
    );
  }
}

class FoodLogItemModel {
  const FoodLogItemModel({
    required this.id,
    required this.loggedDate,
    required this.loggedTime,
    this.foodId,
    this.recipeId,
    this.customName,
    required this.displayName,
    this.brand,
    required this.quantityG,
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    this.recipeServings,
    this.recipeTotalWeightG,
    this.recipeServingWeightG,
  });

  final String id;
  final String loggedDate;
  final String loggedTime;
  final String? foodId;
  final String? recipeId;
  final String? customName;
  final String displayName;
  final String? brand;
  final double quantityG;
  final double kcal;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double? recipeServings;
  final double? recipeTotalWeightG;
  final double? recipeServingWeightG;

  factory FoodLogItemModel.fromJson(Map<String, dynamic> json) {
    return FoodLogItemModel(
      id: json['id'] as String,
      loggedDate: json['logged_date'] as String,
      loggedTime: json['logged_time'] as String,
      foodId: json['food_id'] as String?,
      recipeId: json['recipe_id'] as String?,
      customName: json['custom_name'] as String?,
      displayName: json['display_name'] as String,
      brand: json['brand'] as String?,
      quantityG: (json['quantity_g'] as num).toDouble(),
      kcal: (json['kcal'] as num).toDouble(),
      proteinG: (json['protein_g'] as num).toDouble(),
      fatG: (json['fat_g'] as num).toDouble(),
      carbsG: (json['carbs_g'] as num).toDouble(),
      recipeServings: (json['recipe_servings'] as num?)?.toDouble(),
      recipeTotalWeightG: (json['recipe_total_weight_g'] as num?)?.toDouble(),
      recipeServingWeightG:
          (json['recipe_serving_weight_g'] as num?)?.toDouble(),
    );
  }
}

class DayLogsModel {
  const DayLogsModel({
    required this.date,
    required this.entries,
    required this.totals,
    required this.targets,
    required this.remaining,
  });

  final String date;
  final List<FoodLogItemModel> entries;
  final MacroSummaryModel totals;
  final MacroSummaryModel targets;
  final MacroSummaryModel remaining;

  factory DayLogsModel.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as List<dynamic>;
    return DayLogsModel(
      date: json['date'] as String,
      entries: rawEntries
          .map((e) => FoodLogItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      totals:
          MacroSummaryModel.fromJson(json['totals'] as Map<String, dynamic>),
      targets:
          MacroSummaryModel.fromJson(json['targets'] as Map<String, dynamic>),
      remaining:
          MacroSummaryModel.fromJson(json['remaining'] as Map<String, dynamic>),
    );
  }
}

class DaySummaryModel {
  const DaySummaryModel({
    required this.date,
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.entriesCount,
  });

  final DateTime date;
  final double kcal;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final int entriesCount;

  factory DaySummaryModel.fromJson(Map<String, dynamic> json) {
    return DaySummaryModel(
      date: DateTime.parse(json['date'] as String),
      kcal: (json['kcal'] as num).toDouble(),
      proteinG: (json['protein_g'] as num).toDouble(),
      fatG: (json['fat_g'] as num).toDouble(),
      carbsG: (json['carbs_g'] as num).toDouble(),
      entriesCount: (json['entries_count'] as num).toInt(),
    );
  }
}

class WeightEntryModel {
  const WeightEntryModel({
    required this.id,
    required this.measuredAt,
    required this.weightKg,
    this.bodyFatPct,
    this.trendWeightKg,
    required this.source,
  });

  final String id;
  final DateTime measuredAt;
  final double weightKg;
  final double? bodyFatPct;
  final double? trendWeightKg;
  final String source;

  factory WeightEntryModel.fromJson(Map<String, dynamic> json) {
    return WeightEntryModel(
      id: json['id'] as String,
      measuredAt: DateTime.parse(json['measured_at'] as String),
      weightKg: (json['weight_kg'] as num).toDouble(),
      bodyFatPct: (json['body_fat_pct'] as num?)?.toDouble(),
      trendWeightKg: (json['trend_weight_kg'] as num?)?.toDouble(),
      source: json['source'] as String,
    );
  }
}

class CheckinPreviewModel {
  const CheckinPreviewModel({
    required this.checkinDate,
    required this.periodStart,
    required this.periodEnd,
    required this.avgIntakeKcal,
    required this.daysLoggedCount,
    required this.startTrendWeightKg,
    required this.endTrendWeightKg,
    required this.previousTdeeKcal,
    required this.calculatedTdeeKcal,
    required this.tdeeDeltaKcal,
    required this.newCalorieTarget,
    required this.newProteinG,
    required this.newFatG,
    required this.newCarbsG,
    required this.confidence,
    required this.isDue,
  });

  final DateTime checkinDate;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double avgIntakeKcal;
  final int daysLoggedCount;
  final double startTrendWeightKg;
  final double endTrendWeightKg;
  final double previousTdeeKcal;
  final double calculatedTdeeKcal;
  final double tdeeDeltaKcal;
  final double newCalorieTarget;
  final double newProteinG;
  final double newFatG;
  final double newCarbsG;
  final String confidence;
  final bool isDue;

  factory CheckinPreviewModel.fromJson(Map<String, dynamic> json) {
    return CheckinPreviewModel(
      checkinDate: DateTime.parse(json['checkin_date'] as String),
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      avgIntakeKcal: (json['avg_intake_kcal'] as num).toDouble(),
      daysLoggedCount: (json['days_logged_count'] as num).toInt(),
      startTrendWeightKg: (json['start_trend_weight_kg'] as num).toDouble(),
      endTrendWeightKg: (json['end_trend_weight_kg'] as num).toDouble(),
      previousTdeeKcal: (json['previous_tdee_kcal'] as num).toDouble(),
      calculatedTdeeKcal: (json['calculated_tdee_kcal'] as num).toDouble(),
      tdeeDeltaKcal: (json['tdee_delta_kcal'] as num).toDouble(),
      newCalorieTarget: (json['new_calorie_target'] as num).toDouble(),
      newProteinG: (json['new_protein_g'] as num).toDouble(),
      newFatG: (json['new_fat_g'] as num).toDouble(),
      newCarbsG: (json['new_carbs_g'] as num).toDouble(),
      confidence: json['confidence'] as String,
      isDue: json['is_due'] as bool,
    );
  }
}

class AnalyticsPointModel {
  const AnalyticsPointModel({
    required this.date,
    required this.intakeKcal,
    required this.targetKcal,
    this.weightKg,
    this.trendWeightKg,
    required this.estimatedTdeeKcal,
  });

  final DateTime date;
  final double intakeKcal;
  final double targetKcal;
  final double? weightKg;
  final double? trendWeightKg;
  final double estimatedTdeeKcal;

  factory AnalyticsPointModel.fromJson(Map<String, dynamic> json) {
    return AnalyticsPointModel(
      date: DateTime.parse(json['date'] as String),
      intakeKcal: (json['intake_kcal'] as num).toDouble(),
      targetKcal: (json['target_kcal'] as num?)?.toDouble() ?? 0.0,
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      trendWeightKg: (json['trend_weight_kg'] as num?)?.toDouble(),
      estimatedTdeeKcal: (json['estimated_tdee_kcal'] as num).toDouble(),
    );
  }
}

class DashboardRepository {
  DashboardRepository(this._dio);

  final Dio _dio;

  Future<DayLogsModel> fetchDayLogs(DateTime date) async {
    final formatted = DateFormat('yyyy-MM-dd').format(date);
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/logs/day/$formatted',
    );
    return DayLogsModel.fromJson(res.data!);
  }

  Future<List<DaySummaryModel>> fetchLogsSummary(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final res = await _dio.get<List<dynamic>>(
      '/api/v1/logs/summary',
      queryParameters: {
        'start_date': DateFormat('yyyy-MM-dd').format(startDate),
        'end_date': DateFormat('yyyy-MM-dd').format(endDate),
      },
    );
    return (res.data ?? const [])
        .map((e) => DaySummaryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<WeightEntryModel>> fetchWeights({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final res = await _dio.get<List<dynamic>>(
      '/api/v1/weights',
      queryParameters: {
        if (startDate != null)
          'start_date': DateFormat('yyyy-MM-dd').format(startDate),
        if (endDate != null)
          'end_date': DateFormat('yyyy-MM-dd').format(endDate),
      },
    );
    return (res.data ?? const [])
        .map((e) => WeightEntryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WeightEntryModel> createManualWeight({
    required DateTime measuredAt,
    required double weightKg,
    double? bodyFatPct,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/weights',
      data: {
        'measured_at': measuredAt.toUtc().toIso8601String(),
        'weight_kg': weightKg,
        if (bodyFatPct != null) 'body_fat_pct': bodyFatPct,
      },
    );
    return WeightEntryModel.fromJson(res.data!);
  }

  Future<CheckinPreviewModel> fetchCheckinPreview() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/checkins/preview',
    );
    return CheckinPreviewModel.fromJson(res.data!);
  }

  Future<List<AnalyticsPointModel>> fetchAnalytics(int days) async {
    final res = await _dio.get<List<dynamic>>(
      '/api/v1/checkins/analytics',
      queryParameters: {'days': days},
    );
    return (res.data ?? const [])
        .map((e) => AnalyticsPointModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AnalyticsPointModel>> fetchFullAnalytics() async {
    try {
      return await fetchAnalytics(0);
    } on DioException {
      return fetchAnalytics(365);
    }
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(dioProvider)),
);

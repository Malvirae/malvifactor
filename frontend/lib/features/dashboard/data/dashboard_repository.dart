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
    this.stores,
    this.source,
    this.category,
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
  final String? stores;
  final String? source;
  final String? category;
  final double quantityG;
  final double kcal;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double? recipeServings;
  final double? recipeTotalWeightG;
  final double? recipeServingWeightG;

  factory FoodLogItemModel.fromJson(Map<String, dynamic> json) {
    final foodId = json['food_id'] as String?;
    final recipeId = json['recipe_id'] as String?;
    final rawSource = json['source'] as String?;
    final inferredSource = rawSource ??
        (recipeId != null
            ? 'recipe'
            : (foodId == null ? 'quick_add' : null));
    return FoodLogItemModel(
      id: json['id'] as String,
      loggedDate: json['logged_date'] as String,
      loggedTime: json['logged_time'] as String,
      foodId: foodId,
      recipeId: recipeId,
      customName: json['custom_name'] as String?,
      displayName: json['display_name'] as String,
      brand: json['brand'] as String?,
      stores: json['stores'] as String?,
      source: inferredSource,
      category: json['category'] as String?,
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
    this.validNutritionDays21d,
    this.windowDays = 21,
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
  final int? validNutritionDays21d;
  final int windowDays;
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
      validNutritionDays21d:
          (json['valid_nutrition_days_21d'] as num?)?.toInt(),
      windowDays: (json['window_days'] as num?)?.toInt() ?? 21,
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

class WeeklyNutritionDayModel {
  const WeeklyNutritionDayModel({
    required this.date,
    required this.dayOfWeek,
    required this.isToday,
    required this.isFuture,
    required this.consumedKcal,
    required this.consumedProteinG,
    required this.consumedFatG,
    required this.consumedCarbsG,
    required this.targetKcal,
    required this.targetProteinG,
    required this.targetFatG,
    required this.targetCarbsG,
  });

  final DateTime date;
  final int dayOfWeek; // 1 = Monday .. 7 = Sunday
  final bool isToday;
  final bool isFuture;
  final double consumedKcal;
  final double consumedProteinG;
  final double consumedFatG;
  final double consumedCarbsG;
  final double targetKcal;
  final double targetProteinG;
  final double targetFatG;
  final double targetCarbsG;

  factory WeeklyNutritionDayModel.fromJson(Map<String, dynamic> json) {
    return WeeklyNutritionDayModel(
      date: DateTime.parse(json['date'] as String),
      dayOfWeek: (json['day_of_week'] as num).toInt(),
      isToday: json['is_today'] as bool,
      isFuture: json['is_future'] as bool,
      consumedKcal: (json['consumed_kcal'] as num).toDouble(),
      consumedProteinG: (json['consumed_protein_g'] as num).toDouble(),
      consumedFatG: (json['consumed_fat_g'] as num).toDouble(),
      consumedCarbsG: (json['consumed_carbs_g'] as num).toDouble(),
      targetKcal: (json['target_kcal'] as num).toDouble(),
      targetProteinG: (json['target_protein_g'] as num).toDouble(),
      targetFatG: (json['target_fat_g'] as num).toDouble(),
      targetCarbsG: (json['target_carbs_g'] as num).toDouble(),
    );
  }
}

class WeeklyNutritionTotalsModel {
  const WeeklyNutritionTotalsModel({
    required this.consumedKcal,
    required this.consumedProteinG,
    required this.consumedFatG,
    required this.consumedCarbsG,
    required this.targetKcal,
    required this.targetProteinG,
    required this.targetFatG,
    required this.targetCarbsG,
  });

  final double consumedKcal;
  final double consumedProteinG;
  final double consumedFatG;
  final double consumedCarbsG;
  final double targetKcal;
  final double targetProteinG;
  final double targetFatG;
  final double targetCarbsG;

  factory WeeklyNutritionTotalsModel.fromJson(Map<String, dynamic> json) {
    return WeeklyNutritionTotalsModel(
      consumedKcal: (json['consumed_kcal'] as num).toDouble(),
      consumedProteinG: (json['consumed_protein_g'] as num).toDouble(),
      consumedFatG: (json['consumed_fat_g'] as num).toDouble(),
      consumedCarbsG: (json['consumed_carbs_g'] as num).toDouble(),
      targetKcal: (json['target_kcal'] as num).toDouble(),
      targetProteinG: (json['target_protein_g'] as num).toDouble(),
      targetFatG: (json['target_fat_g'] as num).toDouble(),
      targetCarbsG: (json['target_carbs_g'] as num).toDouble(),
    );
  }
}

class WeeklyNutritionModel {
  const WeeklyNutritionModel({
    required this.weekStart,
    required this.weekEnd,
    required this.days,
    required this.weekTotals,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final List<WeeklyNutritionDayModel> days;
  final WeeklyNutritionTotalsModel weekTotals;

  factory WeeklyNutritionModel.fromJson(Map<String, dynamic> json) {
    return WeeklyNutritionModel(
      weekStart: DateTime.parse(json['week_start'] as String),
      weekEnd: DateTime.parse(json['week_end'] as String),
      days: (json['days'] as List<dynamic>)
          .map(
            (e) =>
                WeeklyNutritionDayModel.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      weekTotals: WeeklyNutritionTotalsModel.fromJson(
        json['week_totals'] as Map<String, dynamic>,
      ),
    );
  }

  /// Graceful fallback when talking to an older backend before restart.
  factory WeeklyNutritionModel.fallback({
    required DateTime today,
    required List<DaySummaryModel> summary,
    required MacroSummaryModel defaultTargets,
  }) {
    final todayDate = DateTime(today.year, today.month, today.day);
    final monday = todayDate.subtract(Duration(days: todayDate.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final byDate = <String, DaySummaryModel>{
      for (final s in summary)
        DateFormat('yyyy-MM-dd').format(s.date): s,
    };

    final days = <WeeklyNutritionDayModel>[];
    double cK = 0, cP = 0, cF = 0, cC = 0;
    double tK = 0, tP = 0, tF = 0, tC = 0;
    for (var i = 0; i < 7; i++) {
      final d = monday.add(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(d);
      final s = byDate[key];
      final ck = s?.kcal ?? 0.0;
      final cp = s?.proteinG ?? 0.0;
      final cf = s?.fatG ?? 0.0;
      final cc = s?.carbsG ?? 0.0;
      cK += ck;
      cP += cp;
      cF += cf;
      cC += cc;
      tK += defaultTargets.kcal;
      tP += defaultTargets.proteinG;
      tF += defaultTargets.fatG;
      tC += defaultTargets.carbsG;
      days.add(
        WeeklyNutritionDayModel(
          date: d,
          dayOfWeek: i + 1,
          isToday: d == todayDate,
          isFuture: d.isAfter(todayDate),
          consumedKcal: ck,
          consumedProteinG: cp,
          consumedFatG: cf,
          consumedCarbsG: cc,
          targetKcal: defaultTargets.kcal,
          targetProteinG: defaultTargets.proteinG,
          targetFatG: defaultTargets.fatG,
          targetCarbsG: defaultTargets.carbsG,
        ),
      );
    }

    return WeeklyNutritionModel(
      weekStart: monday,
      weekEnd: sunday,
      days: days,
      weekTotals: WeeklyNutritionTotalsModel(
        consumedKcal: cK,
        consumedProteinG: cP,
        consumedFatG: cF,
        consumedCarbsG: cC,
        targetKcal: tK,
        targetProteinG: tP,
        targetFatG: tF,
        targetCarbsG: tC,
      ),
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

  Future<WeeklyNutritionModel> fetchWeeklyNutrition({
    DateTime? referenceDate,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/dashboard/weekly-nutrition',
      queryParameters: {
        if (referenceDate != null)
          'reference_date': DateFormat('yyyy-MM-dd').format(referenceDate),
      },
    );
    return WeeklyNutritionModel.fromJson(res.data!);
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(dioProvider)),
);

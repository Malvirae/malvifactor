import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:malvifactor/core/network/dio_client.dart';

class FoodModel {
  const FoodModel({
    required this.id,
    required this.source,
    this.externalId,
    required this.name,
    this.brand,
    this.stores,
    required this.servingSizeG,
    this.servingLabel,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
    required this.fiberPer100g,
    this.lastQuantityG,
    this.servings,
    this.totalWeightG,
    this.servingWeightG,
    this.kcalPerServing,
    this.proteinPerServing,
    this.fatPerServing,
    this.carbsPerServing,
  });

  final String id;
  final String source;
  final String? externalId;
  final String name;
  final String? brand;
  final String? stores;
  final double servingSizeG;
  final String? servingLabel;
  final double kcalPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
  final double fiberPer100g;
  final double? lastQuantityG;
  final double? servings;
  final double? totalWeightG;
  final double? servingWeightG;
  final double? kcalPerServing;
  final double? proteinPerServing;
  final double? fatPerServing;
  final double? carbsPerServing;

  double get defaultQuantityG => (lastQuantityG != null && lastQuantityG! > 0)
      ? lastQuantityG!
      : ((servingWeightG != null && servingWeightG! > 0)
          ? servingWeightG!
          : (servingSizeG > 0 ? servingSizeG : 100.0));

  factory FoodModel.fromJson(Map<String, dynamic> json) {
    return FoodModel(
      id: json['id'] as String,
      source: json['source'] as String,
      externalId: json['external_id'] as String?,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      stores: json['stores'] as String?,
      servingSizeG: (json['serving_size_g'] as num).toDouble(),
      servingLabel: json['serving_label'] as String?,
      kcalPer100g: (json['kcal_per_100g'] as num).toDouble(),
      proteinPer100g: (json['protein_per_100g'] as num).toDouble(),
      fatPer100g: (json['fat_per_100g'] as num).toDouble(),
      carbsPer100g: (json['carbs_per_100g'] as num).toDouble(),
      fiberPer100g: (json['fiber_per_100g'] as num).toDouble(),
      lastQuantityG: (json['last_quantity_g'] as num?)?.toDouble(),
      servings: (json['servings'] as num?)?.toDouble(),
      totalWeightG: (json['total_weight_g'] as num?)?.toDouble(),
      servingWeightG: (json['serving_weight_g'] as num?)?.toDouble(),
      kcalPerServing: (json['kcal_per_serving'] as num?)?.toDouble(),
      proteinPerServing: (json['protein_per_serving'] as num?)?.toDouble(),
      fatPerServing: (json['fat_per_serving'] as num?)?.toDouble(),
      carbsPerServing: (json['carbs_per_serving'] as num?)?.toDouble(),
    );
  }
}

class FoodSuggestionItemModel {
  const FoodSuggestionItemModel({
    required this.id,
    required this.itemType,
    required this.source,
    required this.name,
    this.brand,
    this.stores,
    required this.servingSizeG,
    this.servingLabel,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
    required this.fiberPer100g,
    required this.lastQuantityG,
    this.lastServingLabel,
    required this.previewKcal,
    required this.previewProteinG,
    required this.previewFatG,
    required this.previewCarbsG,
    required this.lastLoggedAt,
    required this.timesLoggedAtHour,
    this.servings,
    this.totalWeightG,
    this.servingWeightG,
    this.kcalPerServing,
    this.proteinPerServing,
    this.fatPerServing,
    this.carbsPerServing,
  });

  final String id;
  final String itemType; // 'standard' | 'custom' | 'recipe'
  final String source; // 'ciqual' | 'off' | 'custom' | 'recipe'
  final String name;
  final String? brand;
  final String? stores;
  final double servingSizeG;
  final String? servingLabel;
  final double kcalPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
  final double fiberPer100g;
  final double lastQuantityG;
  final String? lastServingLabel;
  final double previewKcal;
  final double previewProteinG;
  final double previewFatG;
  final double previewCarbsG;
  final DateTime lastLoggedAt;
  final int timesLoggedAtHour;
  final double? servings;
  final double? totalWeightG;
  final double? servingWeightG;
  final double? kcalPerServing;
  final double? proteinPerServing;
  final double? fatPerServing;
  final double? carbsPerServing;

  bool get isRecipe => itemType == 'recipe';
  bool get isQuickAdd => itemType == 'quick_add';

  FoodModel toFoodModel() => FoodModel(
        id: id,
        source: source,
        name: name,
        brand: brand,
        stores: stores,
        servingSizeG: servingSizeG,
        servingLabel: servingLabel,
        kcalPer100g: kcalPer100g,
        proteinPer100g: proteinPer100g,
        fatPer100g: fatPer100g,
        carbsPer100g: carbsPer100g,
        fiberPer100g: fiberPer100g,
        lastQuantityG: lastQuantityG,
        servings: servings,
        totalWeightG: totalWeightG,
        servingWeightG: servingWeightG,
        kcalPerServing: kcalPerServing,
        proteinPerServing: proteinPerServing,
        fatPerServing: fatPerServing,
        carbsPerServing: carbsPerServing,
      );

  factory FoodSuggestionItemModel.fromJson(Map<String, dynamic> json) {
    return FoodSuggestionItemModel(
      id: json['id'] as String,
      itemType: json['item_type'] as String,
      source: json['source'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      stores: json['stores'] as String?,
      servingSizeG: (json['serving_size_g'] as num).toDouble(),
      servingLabel: json['serving_label'] as String?,
      kcalPer100g: (json['kcal_per_100g'] as num).toDouble(),
      proteinPer100g: (json['protein_per_100g'] as num).toDouble(),
      fatPer100g: (json['fat_per_100g'] as num).toDouble(),
      carbsPer100g: (json['carbs_per_100g'] as num).toDouble(),
      fiberPer100g: (json['fiber_per_100g'] as num?)?.toDouble() ?? 0.0,
      lastQuantityG: (json['last_quantity_g'] as num).toDouble(),
      lastServingLabel: json['last_serving_label'] as String?,
      previewKcal: (json['preview_kcal'] as num).toDouble(),
      previewProteinG: (json['preview_protein_g'] as num).toDouble(),
      previewFatG: (json['preview_fat_g'] as num).toDouble(),
      previewCarbsG: (json['preview_carbs_g'] as num).toDouble(),
      lastLoggedAt: DateTime.parse(json['last_logged_at'] as String),
      timesLoggedAtHour: (json['times_logged_at_hour'] as num?)?.toInt() ?? 0,
      servings: (json['servings'] as num?)?.toDouble(),
      totalWeightG: (json['total_weight_g'] as num?)?.toDouble(),
      servingWeightG: (json['serving_weight_g'] as num?)?.toDouble(),
      kcalPerServing: (json['kcal_per_serving'] as num?)?.toDouble(),
      proteinPerServing: (json['protein_per_serving'] as num?)?.toDouble(),
      fatPerServing: (json['fat_per_serving'] as num?)?.toDouble(),
      carbsPerServing: (json['carbs_per_serving'] as num?)?.toDouble(),
    );
  }
}

class FoodSuggestionsResponseModel {
  const FoodSuggestionsResponseModel({
    required this.targetHour,
    required this.timePicks,
    required this.recentFoods,
  });

  final int targetHour;
  final List<FoodSuggestionItemModel> timePicks;
  final List<FoodSuggestionItemModel> recentFoods;

  factory FoodSuggestionsResponseModel.fromJson(Map<String, dynamic> json) {
    return FoodSuggestionsResponseModel(
      targetHour: (json['target_hour'] as num).toInt(),
      timePicks: (json['time_picks'] as List<dynamic>? ?? const [])
          .map((e) =>
              FoodSuggestionItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      recentFoods: (json['recent_foods'] as List<dynamic>? ?? const [])
          .map((e) =>
              FoodSuggestionItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FoodRepository {
  FoodRepository(this._dio);

  final Dio _dio;

  String _formatTime(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm:00';
  }

  Future<FoodSuggestionsResponseModel> fetchSuggestions({
    required int targetHour,
    int limitPicks = 8,
    int limitRecent = 30,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/foods/suggestions',
      queryParameters: {
        'target_hour': targetHour,
        'limit_picks': limitPicks,
        'limit_recent': limitRecent,
      },
    );
    return FoodSuggestionsResponseModel.fromJson(res.data!);
  }

  Future<List<FoodModel>> searchFoods(String query, {int limit = 30}) async {
    final res = await _dio.get<List<dynamic>>(
      '/api/v1/foods/search',
      queryParameters: {'q': query, 'limit': limit},
    );
    return (res.data ?? const [])
        .map((e) => FoodModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FoodModel> getFoodByBarcode(String barcode) async {
    final clean = barcode.trim();
    final res = await _dio.get<Map<String, dynamic>>(
      '/api/v1/foods/barcode/$clean',
    );
    return FoodModel.fromJson(res.data!);
  }

  Future<FoodModel> createCustomFood({
    required String name,
    String? brand,
    String? externalId,
    double servingSizeG = 100.0,
    required double kcalPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
    double fiberPer100g = 0.0,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/foods',
      data: {
        'name': name,
        if (brand != null && brand.trim().isNotEmpty) 'brand': brand.trim(),
        if (externalId != null && externalId.trim().isNotEmpty)
          'external_id': externalId.trim(),
        'serving_size_g': servingSizeG,
        'kcal_per_100g': kcalPer100g,
        'protein_per_100g': proteinPer100g,
        'fat_per_100g': fatPer100g,
        'carbs_per_100g': carbsPer100g,
        'fiber_per_100g': fiberPer100g,
      },
    );
    return FoodModel.fromJson(res.data!);
  }

  Future<List<FoodModel>> listCustomFoods() async {
    final res = await _dio.get<List<dynamic>>('/api/v1/foods/custom');
    return (res.data ?? const [])
        .map((e) => FoodModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FoodModel> updateCustomFood({
    required String foodId,
    required String name,
    String? brand,
    required double servingSizeG,
    required double kcalPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
    required double fiberPer100g,
  }) async {
    final res = await _dio.put<Map<String, dynamic>>(
      '/api/v1/foods/$foodId',
      data: {
        'name': name.trim(),
        'brand': brand?.trim() ?? '',
        'serving_size_g': servingSizeG,
        'kcal_per_100g': kcalPer100g,
        'protein_per_100g': proteinPer100g,
        'fat_per_100g': fatPer100g,
        'carbs_per_100g': carbsPer100g,
        'fiber_per_100g': fiberPer100g,
      },
    );
    return FoodModel.fromJson(res.data!);
  }

  Future<void> deleteCustomFood(String foodId) async {
    await _dio.delete<void>('/api/v1/foods/$foodId');
  }

  Future<FoodModel> customizeFood({
    required String foodId,
    required String name,
    String? brand,
    required double kcalPer100g,
    required double proteinPer100g,
    required double fatPer100g,
    required double carbsPer100g,
    double? fiberPer100g,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/foods/$foodId/customize',
      data: {
        'name': name.trim(),
        if (brand != null) 'brand': brand.trim(),
        'kcal_per_100g': kcalPer100g,
        'protein_per_100g': proteinPer100g,
        'fat_per_100g': fatPer100g,
        'carbs_per_100g': carbsPer100g,
        if (fiberPer100g != null) 'fiber_per_100g': fiberPer100g,
      },
    );
    return FoodModel.fromJson(res.data!);
  }

  Future<void> logFood({
    required DateTime loggedDate,
    required TimeOfDay loggedTime,
    required String foodId,
    required double quantityG,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/logs',
      data: {
        'logged_date': DateFormat('yyyy-MM-dd').format(loggedDate),
        'logged_time': _formatTime(loggedTime),
        'food_id': foodId,
        'quantity_g': quantityG,
      },
    );
  }

  Future<void> logRecipe({
    required DateTime loggedDate,
    required TimeOfDay loggedTime,
    required String recipeId,
    required double quantityG,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/logs',
      data: {
        'logged_date': DateFormat('yyyy-MM-dd').format(loggedDate),
        'logged_time': _formatTime(loggedTime),
        'recipe_id': recipeId,
        'quantity_g': quantityG,
      },
    );
  }

  Future<void> logQuickAdd({
    required DateTime loggedDate,
    required TimeOfDay loggedTime,
    required String customName,
    required double kcal,
    required double proteinG,
    required double fatG,
    required double carbsG,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/logs',
      data: {
        'logged_date': DateFormat('yyyy-MM-dd').format(loggedDate),
        'logged_time': _formatTime(loggedTime),
        'custom_name': customName,
        'kcal': kcal,
        'protein_g': proteinG,
        'fat_g': fatG,
        'carbs_g': carbsG,
      },
    );
  }

  Future<void> batchCreateLogs({
    required DateTime loggedDate,
    required TimeOfDay loggedTime,
    required List<Map<String, dynamic>> items,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/logs/batch',
      data: {
        'logged_date': DateFormat('yyyy-MM-dd').format(loggedDate),
        'logged_time': _formatTime(loggedTime),
        'items': items,
      },
    );
  }
}

final foodRepositoryProvider = Provider<FoodRepository>(
  (ref) => FoodRepository(ref.watch(dioProvider)),
);

final customFoodsProvider = FutureProvider<List<FoodModel>>((ref) {
  return ref.watch(foodRepositoryProvider).listCustomFoods();
});

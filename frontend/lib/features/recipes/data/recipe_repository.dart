import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:malvifactor/core/network/dio_client.dart';

class RecipeSummaryModel {
  const RecipeSummaryModel({
    required this.id,
    required this.name,
    this.description,
    required this.totalWeightG,
    required this.servingsCount,
    this.servingWeightG,
    this.kcalPerServing,
    this.proteinPerServing,
    this.fatPerServing,
    this.carbsPerServing,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
    required this.isShared,
  });

  final String id;
  final String name;
  final String? description;
  final double totalWeightG;
  final double servingsCount;
  final double? servingWeightG;
  final double? kcalPerServing;
  final double? proteinPerServing;
  final double? fatPerServing;
  final double? carbsPerServing;
  final double kcalPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
  final bool isShared;

  bool get hasServings =>
      servingsCount > 0 && resolvedServingWeightG != null && resolvedServingWeightG! > 0;

  double? get resolvedServingWeightG {
    if (servingWeightG != null && servingWeightG! > 0) return servingWeightG;
    if (servingsCount > 0 && totalWeightG > 0) {
      return double.parse((totalWeightG / servingsCount).toStringAsFixed(1));
    }
    return null;
  }

  double get perServingKcal {
    if (kcalPerServing != null) return kcalPerServing!;
    final sw = resolvedServingWeightG;
    if (sw == null) return kcalPer100g;
    return kcalPer100g * sw / 100.0;
  }

  double get perServingProteinG {
    if (proteinPerServing != null) return proteinPerServing!;
    final sw = resolvedServingWeightG;
    if (sw == null) return proteinPer100g;
    return proteinPer100g * sw / 100.0;
  }

  double get perServingFatG {
    if (fatPerServing != null) return fatPerServing!;
    final sw = resolvedServingWeightG;
    if (sw == null) return fatPer100g;
    return fatPer100g * sw / 100.0;
  }

  double get perServingCarbsG {
    if (carbsPerServing != null) return carbsPerServing!;
    final sw = resolvedServingWeightG;
    if (sw == null) return carbsPer100g;
    return carbsPer100g * sw / 100.0;
  }

  factory RecipeSummaryModel.fromJson(Map<String, dynamic> json) {
    final totalW = (json['total_weight_g'] as num).toDouble();
    final servings = ((json['servings'] ?? json['servings_count']) as num).toDouble();
    final kcal100 = (json['kcal_per_100g'] as num).toDouble();
    final p100 = (json['protein_per_100g'] as num).toDouble();
    final f100 = (json['fat_per_100g'] as num).toDouble();
    final c100 = (json['carbs_per_100g'] as num).toDouble();
    final sw = (json['serving_weight_g'] as num?)?.toDouble() ??
        (servings > 0 ? double.parse((totalW / servings).toStringAsFixed(1)) : null);
    return RecipeSummaryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      totalWeightG: totalW,
      servingsCount: servings,
      servingWeightG: sw,
      kcalPerServing: (json['kcal_per_serving'] as num?)?.toDouble() ??
          (sw != null ? kcal100 * sw / 100.0 : null),
      proteinPerServing: (json['protein_per_serving'] as num?)?.toDouble() ??
          (sw != null ? p100 * sw / 100.0 : null),
      fatPerServing: (json['fat_per_serving'] as num?)?.toDouble() ??
          (sw != null ? f100 * sw / 100.0 : null),
      carbsPerServing: (json['carbs_per_serving'] as num?)?.toDouble() ??
          (sw != null ? c100 * sw / 100.0 : null),
      kcalPer100g: kcal100,
      proteinPer100g: p100,
      fatPer100g: f100,
      carbsPer100g: c100,
      isShared: json['is_shared'] as bool,
    );
  }
}

class RecipeIngredientDetailModel {
  const RecipeIngredientDetailModel({
    required this.id,
    required this.foodId,
    required this.foodName,
    this.foodBrand,
    required this.quantityG,
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  final String id;
  final String foodId;
  final String foodName;
  final String? foodBrand;
  final double quantityG;
  final double kcal;
  final double proteinG;
  final double fatG;
  final double carbsG;

  factory RecipeIngredientDetailModel.fromJson(Map<String, dynamic> json) {
    return RecipeIngredientDetailModel(
      id: json['id'] as String,
      foodId: json['food_id'] as String,
      foodName: json['food_name'] as String,
      foodBrand: json['food_brand'] as String?,
      quantityG: (json['quantity_g'] as num).toDouble(),
      kcal: (json['kcal'] as num).toDouble(),
      proteinG: (json['protein_g'] as num).toDouble(),
      fatG: (json['fat_g'] as num).toDouble(),
      carbsG: (json['carbs_g'] as num).toDouble(),
    );
  }
}

class RecipeDetailModel extends RecipeSummaryModel {
  const RecipeDetailModel({
    required super.id,
    required super.name,
    super.description,
    required super.totalWeightG,
    required super.servingsCount,
    super.servingWeightG,
    super.kcalPerServing,
    super.proteinPerServing,
    super.fatPerServing,
    super.carbsPerServing,
    required super.kcalPer100g,
    required super.proteinPer100g,
    required super.fatPer100g,
    required super.carbsPer100g,
    required super.isShared,
    required this.ingredients,
  });

  final List<RecipeIngredientDetailModel> ingredients;

  factory RecipeDetailModel.fromJson(Map<String, dynamic> json) {
    final summary = RecipeSummaryModel.fromJson(json);
    final rawIngredients = json['ingredients'] as List<dynamic>? ?? const [];
    return RecipeDetailModel(
      id: summary.id,
      name: summary.name,
      description: summary.description,
      totalWeightG: summary.totalWeightG,
      servingsCount: summary.servingsCount,
      servingWeightG: summary.servingWeightG,
      kcalPerServing: summary.kcalPerServing,
      proteinPerServing: summary.proteinPerServing,
      fatPerServing: summary.fatPerServing,
      carbsPerServing: summary.carbsPerServing,
      kcalPer100g: summary.kcalPer100g,
      proteinPer100g: summary.proteinPer100g,
      fatPer100g: summary.fatPer100g,
      carbsPer100g: summary.carbsPer100g,
      isShared: summary.isShared,
      ingredients: rawIngredients
          .map(
            (e) =>
                RecipeIngredientDetailModel.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class RecipeRepository {
  RecipeRepository(this._dio);

  final Dio _dio;

  Future<List<RecipeSummaryModel>> listRecipes({String q = ''}) async {
    final res = await _dio.get<List<dynamic>>(
      '/api/v1/recipes',
      queryParameters: q.trim().isNotEmpty ? {'q': q.trim()} : null,
    );
    return (res.data ?? const [])
        .map((e) => RecipeSummaryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RecipeDetailModel> getRecipe(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/api/v1/recipes/$id');
    return RecipeDetailModel.fromJson(res.data!);
  }

  Future<RecipeDetailModel> createRecipe({
    required String name,
    String? description,
    double servingsCount = 1.0,
    bool isShared = true,
    double? finalWeightG,
    required List<Map<String, dynamic>> ingredients,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/recipes',
      data: {
        'name': name.trim(),
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        'servings_count': servingsCount,
        'is_shared': isShared,
        if (finalWeightG != null) 'final_weight_g': finalWeightG,
        'ingredients': ingredients,
      },
    );
    return RecipeDetailModel.fromJson(res.data!);
  }

  Future<RecipeDetailModel> updateRecipe({
    required String id,
    required String name,
    String? description,
    double servingsCount = 1.0,
    bool isShared = true,
    double? finalWeightG,
    required List<Map<String, dynamic>> ingredients,
  }) async {
    final res = await _dio.put<Map<String, dynamic>>(
      '/api/v1/recipes/$id',
      data: {
        'name': name.trim(),
        'description': description?.trim() ?? '',
        'servings_count': servingsCount,
        'is_shared': isShared,
        if (finalWeightG != null) 'final_weight_g': finalWeightG,
        'ingredients': ingredients,
      },
    );
    return RecipeDetailModel.fromJson(res.data!);
  }

  Future<void> deleteRecipe(String id) async {
    await _dio.delete<void>('/api/v1/recipes/$id');
  }
}

final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => RecipeRepository(ref.watch(dioProvider)),
);

final recipesListProvider =
    FutureProvider.family<List<RecipeSummaryModel>, String>((ref, query) {
  return ref.watch(recipeRepositoryProvider).listRecipes(q: query);
});

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
  final double kcalPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
  final bool isShared;

  factory RecipeSummaryModel.fromJson(Map<String, dynamic> json) {
    return RecipeSummaryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      totalWeightG: (json['total_weight_g'] as num).toDouble(),
      servingsCount: (json['servings_count'] as num).toDouble(),
      kcalPer100g: (json['kcal_per_100g'] as num).toDouble(),
      proteinPer100g: (json['protein_per_100g'] as num).toDouble(),
      fatPer100g: (json['fat_per_100g'] as num).toDouble(),
      carbsPer100g: (json['carbs_per_100g'] as num).toDouble(),
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
    required super.kcalPer100g,
    required super.proteinPer100g,
    required super.fatPer100g,
    required super.carbsPer100g,
    required super.isShared,
    required this.ingredients,
  });

  final List<RecipeIngredientDetailModel> ingredients;

  factory RecipeDetailModel.fromJson(Map<String, dynamic> json) {
    final rawIngredients = json['ingredients'] as List<dynamic>? ?? const [];
    return RecipeDetailModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      totalWeightG: (json['total_weight_g'] as num).toDouble(),
      servingsCount: (json['servings_count'] as num).toDouble(),
      kcalPer100g: (json['kcal_per_100g'] as num).toDouble(),
      proteinPer100g: (json['protein_per_100g'] as num).toDouble(),
      fatPer100g: (json['fat_per_100g'] as num).toDouble(),
      carbsPer100g: (json['carbs_per_100g'] as num).toDouble(),
      isShared: json['is_shared'] as bool,
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

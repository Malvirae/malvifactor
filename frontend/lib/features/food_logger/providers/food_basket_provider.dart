import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/journal/presentation/journal_screen.dart';
import 'package:malvifactor/features/recipes/data/recipe_repository.dart';

final foodSuggestionsProvider =
    FutureProvider.family<FoodSuggestionsResponseModel, int>(
  (ref, targetHour) async {
    return ref
        .watch(foodRepositoryProvider)
        .fetchSuggestions(targetHour: targetHour);
  },
);

class BasketItem {
  const BasketItem({
    required this.localId,
    required this.itemType,
    this.foodId,
    this.recipeId,
    this.customName,
    required this.name,
    this.brand,
    required this.quantityG,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    this.recipeServings,
    this.recipeTotalWeightG,
    this.recipeServingWeightG,
  });

  final String localId;
  final String itemType; // 'standard' | 'custom' | 'recipe' | 'quick'
  final String? foodId;
  final String? recipeId;
  final String? customName;
  final String name;
  final String? brand;
  final double quantityG;
  final double kcalPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
  final double kcal;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double? recipeServings;
  final double? recipeTotalWeightG;
  final double? recipeServingWeightG;

  bool get isQuickAdd => itemType == 'quick';

  BasketItem withQuantity(double newQtyG) {
    if (isQuickAdd) {
      return BasketItem(
        localId: localId,
        itemType: itemType,
        foodId: foodId,
        recipeId: recipeId,
        customName: customName,
        name: name,
        brand: brand,
        quantityG: newQtyG,
        kcalPer100g: kcalPer100g,
        proteinPer100g: proteinPer100g,
        fatPer100g: fatPer100g,
        carbsPer100g: carbsPer100g,
        kcal: kcal,
        proteinG: proteinG,
        fatG: fatG,
        carbsG: carbsG,
        recipeServings: recipeServings,
        recipeTotalWeightG: recipeTotalWeightG,
        recipeServingWeightG: recipeServingWeightG,
      );
    }
    final factor = newQtyG / 100.0;
    return BasketItem(
      localId: localId,
      itemType: itemType,
      foodId: foodId,
      recipeId: recipeId,
      customName: customName,
      name: name,
      brand: brand,
      quantityG: newQtyG,
      kcalPer100g: kcalPer100g,
      proteinPer100g: proteinPer100g,
      fatPer100g: fatPer100g,
      carbsPer100g: carbsPer100g,
      kcal: kcalPer100g * factor,
      proteinG: proteinPer100g * factor,
      fatG: fatPer100g * factor,
      carbsG: carbsPer100g * factor,
      recipeServings: recipeServings,
      recipeTotalWeightG: recipeTotalWeightG,
      recipeServingWeightG: recipeServingWeightG,
    );
  }

  Map<String, dynamic> toBatchPayloadItem() {
    if (foodId != null) {
      return {
        'food_id': foodId,
        'quantity_g': quantityG,
      };
    }
    if (recipeId != null) {
      return {
        'recipe_id': recipeId,
        'quantity_g': quantityG,
      };
    }
    return {
      'custom_name': customName ?? name,
      'quantity_g': quantityG,
      'kcal': kcal,
      'protein_g': proteinG,
      'fat_g': fatG,
      'carbs_g': carbsG,
    };
  }
}

class FoodBasketState {
  const FoodBasketState({
    required this.targetDate,
    required this.targetHour,
    this.items = const [],
    this.isSubmitting = false,
  });

  final DateTime targetDate;
  final int targetHour;
  final List<BasketItem> items;
  final bool isSubmitting;

  double get totalKcal => items.fold(0.0, (sum, i) => sum + i.kcal);
  double get totalProteinG => items.fold(0.0, (sum, i) => sum + i.proteinG);
  double get totalFatG => items.fold(0.0, (sum, i) => sum + i.fatG);
  double get totalCarbsG => items.fold(0.0, (sum, i) => sum + i.carbsG);
  int get itemCount => items.length;

  int countFor({String? foodId, String? recipeId, String? quickName}) {
    if (foodId != null) {
      return items.where((i) => i.foodId == foodId).length;
    }
    if (recipeId != null) {
      return items.where((i) => i.recipeId == recipeId).length;
    }
    if (quickName != null) {
      final norm = quickName.trim().toLowerCase();
      return items
          .where((i) => i.isQuickAdd && i.name.trim().toLowerCase() == norm)
          .length;
    }
    return 0;
  }

  FoodBasketState copyWith({
    DateTime? targetDate,
    int? targetHour,
    List<BasketItem>? items,
    bool? isSubmitting,
  }) {
    return FoodBasketState(
      targetDate: targetDate ?? this.targetDate,
      targetHour: targetHour ?? this.targetHour,
      items: items ?? this.items,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }
}

class FoodBasketNotifier extends StateNotifier<FoodBasketState> {
  FoodBasketNotifier(this._ref)
      : super(
          FoodBasketState(
            targetDate: DateTime.now(),
            targetHour: DateTime.now().hour,
          ),
        );

  final Ref _ref;
  int _seq = 0;

  String _nextId() => 'basket_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  void initSession(DateTime date, int hour) {
    state = FoodBasketState(
      targetDate: date,
      targetHour: hour.clamp(0, 23),
      items: const [],
      isSubmitting: false,
    );
  }

  void setTargetHour(int hour) {
    state = state.copyWith(targetHour: hour.clamp(0, 23));
  }

  void addItem(BasketItem item) {
    state = state.copyWith(items: [...state.items, item]);
  }

  void addFood(FoodModel food, {double? quantityG}) {
    final qty = (quantityG != null && quantityG > 0)
        ? quantityG
        : food.defaultQuantityG;
    final factor = qty / 100.0;
    final isRecipe = food.source == 'recipe';
    addItem(
      BasketItem(
        localId: _nextId(),
        itemType: isRecipe
            ? 'recipe'
            : (food.source == 'custom' ? 'custom' : 'standard'),
        foodId: isRecipe ? null : food.id,
        recipeId: isRecipe ? food.id : null,
        name: food.name,
        brand: food.brand,
        quantityG: qty,
        kcalPer100g: food.kcalPer100g,
        proteinPer100g: food.proteinPer100g,
        fatPer100g: food.fatPer100g,
        carbsPer100g: food.carbsPer100g,
        kcal: food.kcalPer100g * factor,
        proteinG: food.proteinPer100g * factor,
        fatG: food.fatPer100g * factor,
        carbsG: food.carbsPer100g * factor,
        recipeServings: isRecipe ? food.servings : null,
        recipeTotalWeightG: isRecipe ? food.totalWeightG : null,
        recipeServingWeightG: isRecipe ? food.servingWeightG : null,
      ),
    );
  }

  void addRecipe(RecipeSummaryModel recipe, {double? quantityG}) {
    final defaultPortionG = recipe.resolvedServingWeightG ?? 100.0;
    final qty = (quantityG != null && quantityG > 0) ? quantityG : defaultPortionG;
    final factor = qty / 100.0;
    addItem(
      BasketItem(
        localId: _nextId(),
        itemType: 'recipe',
        recipeId: recipe.id,
        name: recipe.name,
        quantityG: qty,
        kcalPer100g: recipe.kcalPer100g,
        proteinPer100g: recipe.proteinPer100g,
        fatPer100g: recipe.fatPer100g,
        carbsPer100g: recipe.carbsPer100g,
        kcal: recipe.kcalPer100g * factor,
        proteinG: recipe.proteinPer100g * factor,
        fatG: recipe.fatPer100g * factor,
        carbsG: recipe.carbsPer100g * factor,
        recipeServings: recipe.servingsCount,
        recipeTotalWeightG: recipe.totalWeightG,
        recipeServingWeightG: recipe.resolvedServingWeightG,
      ),
    );
  }

  void addSuggestion(FoodSuggestionItemModel suggestion, {double? quantityG}) {
    if (suggestion.isQuickAdd) {
      addQuickAdd(
        name: suggestion.name,
        kcal: suggestion.previewKcal,
        proteinG: suggestion.previewProteinG,
        fatG: suggestion.previewFatG,
        carbsG: suggestion.previewCarbsG,
      );
      return;
    }
    final qty = (quantityG != null && quantityG > 0)
        ? quantityG
        : suggestion.lastQuantityG;
    final factor = qty / 100.0;
    addItem(
      BasketItem(
        localId: _nextId(),
        itemType: suggestion.itemType,
        foodId: suggestion.isRecipe ? null : suggestion.id,
        recipeId: suggestion.isRecipe ? suggestion.id : null,
        name: suggestion.name,
        brand: suggestion.brand,
        quantityG: qty,
        kcalPer100g: suggestion.kcalPer100g,
        proteinPer100g: suggestion.proteinPer100g,
        fatPer100g: suggestion.fatPer100g,
        carbsPer100g: suggestion.carbsPer100g,
        kcal: suggestion.kcalPer100g * factor,
        proteinG: suggestion.proteinPer100g * factor,
        fatG: suggestion.fatPer100g * factor,
        carbsG: suggestion.carbsPer100g * factor,
        recipeServings: suggestion.isRecipe ? suggestion.servings : null,
        recipeTotalWeightG: suggestion.isRecipe ? suggestion.totalWeightG : null,
        recipeServingWeightG:
            suggestion.isRecipe ? suggestion.servingWeightG : null,
      ),
    );
  }

  void addQuickAdd({
    required String name,
    required double kcal,
    required double proteinG,
    required double fatG,
    required double carbsG,
  }) {
    addItem(
      BasketItem(
        localId: _nextId(),
        itemType: 'quick',
        customName: name.trim(),
        name: name.trim(),
        quantityG: 1.0,
        kcalPer100g: kcal,
        proteinPer100g: proteinG,
        fatPer100g: fatG,
        carbsPer100g: carbsG,
        kcal: kcal,
        proteinG: proteinG,
        fatG: fatG,
        carbsG: carbsG,
      ),
    );
  }

  void updateItemQuantity(String localId, double newQtyG) {
    if (newQtyG <= 0) return;
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.localId == localId) item.withQuantity(newQtyG) else item,
      ],
    );
  }

  void removeItem(String localId) {
    state = state.copyWith(
      items: state.items.where((i) => i.localId != localId).toList(),
    );
  }

  void clearBasket() {
    state = state.copyWith(items: const [], isSubmitting: false);
  }

  Future<String?> submitBasket() async {
    if (state.items.isEmpty || state.isSubmitting) return null;
    state = state.copyWith(isSubmitting: true);
    try {
      await _ref.read(foodRepositoryProvider).batchCreateLogs(
            loggedDate: state.targetDate,
            loggedTime: TimeOfDay(hour: state.targetHour, minute: 0),
            items: state.items.map((e) => e.toBatchPayloadItem()).toList(),
          );
      _ref.invalidate(journalDayProvider);
      _ref.invalidate(dashboardProvider);
      _ref.invalidate(fullMetricContextProvider);
      _ref.invalidate(foodSuggestionsProvider);
      clearBasket();
      return null;
    } catch (e) {
      state = state.copyWith(isSubmitting: false);
      return e.toString();
    }
  }
}

final foodBasketProvider =
    StateNotifierProvider<FoodBasketNotifier, FoodBasketState>(
  (ref) => FoodBasketNotifier(ref),
);

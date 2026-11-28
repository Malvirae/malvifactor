import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:malvifactor/core/network/dio_client.dart';

class UserProfileModel {
  const UserProfileModel({
    required this.userId,
    required this.sex,
    required this.birthDate,
    required this.heightCm,
    required this.activityLevel,
    required this.goalType,
    required this.targetRateKgPerWeek,
    required this.proteinPreference,
    required this.dietStyle,
    required this.checkinDay,
    required this.initialTdeeKcal,
    required this.currentTdeeKcal,
    required this.currentCalorieTarget,
    required this.currentProteinG,
    required this.currentFatG,
    required this.currentCarbsG,
    this.targetWeightKg,
    this.onboardingCompleted = false,
    required this.updatedAt,
  });

  final String userId;
  final String sex;
  final DateTime birthDate;
  final double heightCm;
  final String activityLevel;
  final String goalType;
  final double targetRateKgPerWeek;
  final String proteinPreference;
  final String dietStyle;
  final int checkinDay;
  final double initialTdeeKcal;
  final double currentTdeeKcal;
  final double currentCalorieTarget;
  final double currentProteinG;
  final double currentFatG;
  final double currentCarbsG;
  final double? targetWeightKg;
  final bool onboardingCompleted;
  final DateTime updatedAt;

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      userId: json['user_id'] as String,
      sex: json['sex'] as String,
      birthDate: DateTime.parse(json['birth_date'] as String),
      heightCm: (json['height_cm'] as num).toDouble(),
      activityLevel: json['activity_level'] as String,
      goalType: json['goal_type'] as String,
      targetRateKgPerWeek: (json['target_rate_kg_per_week'] as num).toDouble(),
      proteinPreference: json['protein_preference'] as String,
      dietStyle: json['diet_style'] as String,
      checkinDay: (json['checkin_day'] as num).toInt(),
      initialTdeeKcal: (json['initial_tdee_kcal'] as num).toDouble(),
      currentTdeeKcal: (json['current_tdee_kcal'] as num).toDouble(),
      currentCalorieTarget:
          (json['current_calorie_target'] as num).toDouble(),
      currentProteinG: (json['current_protein_g'] as num).toDouble(),
      currentFatG: (json['current_fat_g'] as num).toDouble(),
      currentCarbsG: (json['current_carbs_g'] as num).toDouble(),
      targetWeightKg: (json['target_weight_kg'] as num?)?.toDouble(),
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class ProfileRepository {
  ProfileRepository(this._dio);

  final Dio _dio;

  Future<UserProfileModel> fetchProfile() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/v1/profile');
    return UserProfileModel.fromJson(res.data!);
  }

  Future<UserProfileModel> updateProfile({
    required String sex,
    required DateTime birthDate,
    required double heightCm,
    required String activityLevel,
    required String goalType,
    required double targetRateKgPerWeek,
    required String proteinPreference,
    required String dietStyle,
    required int checkinDay,
    bool recalculateTargets = true,
    double? referenceWeightKg,
  }) async {
    final payload = <String, dynamic>{
      'sex': sex,
      'birth_date': DateFormat('yyyy-MM-dd').format(birthDate),
      'height_cm': heightCm,
      'activity_level': activityLevel,
      'goal_type': goalType,
      'target_rate_kg_per_week': targetRateKgPerWeek,
      'protein_preference': proteinPreference,
      'diet_style': dietStyle,
      'checkin_day': checkinDay,
      'recalculate_targets': recalculateTargets,
      if (referenceWeightKg != null) 'reference_weight_kg': referenceWeightKg,
    };

    final res = await _dio.put<Map<String, dynamic>>(
      '/api/v1/profile',
      data: payload,
    );
    return UserProfileModel.fromJson(res.data!);
  }

  Future<UserProfileModel> completeOnboarding({
    required String displayName,
    required String sex,
    required DateTime birthDate,
    required double heightCm,
    required double weightKg,
    double? bodyFatPct,
    required String neatLevel,
    required int workoutsPerWeek,
    required String workoutType,
    int? manualInitialTdeeKcal,
    required String goalType,
    required double targetRateKgPerWeek,
    double? targetWeightKg,
    required String proteinPreference,
    required String dietStyle,
    required int checkinDay,
  }) async {
    final payload = <String, dynamic>{
      'display_name': displayName.trim(),
      'sex': sex,
      'birth_date': DateFormat('yyyy-MM-dd').format(birthDate),
      'height_cm': heightCm,
      'weight_kg': weightKg,
      if (bodyFatPct != null) 'body_fat_pct': bodyFatPct,
      'neat_level': neatLevel,
      'workouts_per_week': workoutsPerWeek,
      'workout_type': workoutType,
      if (manualInitialTdeeKcal != null && manualInitialTdeeKcal > 0)
        'manual_initial_tdee_kcal': manualInitialTdeeKcal,
      'goal_type': goalType,
      'target_rate_kg_per_week': targetRateKgPerWeek,
      if (targetWeightKg != null) 'target_weight_kg': targetWeightKg,
      'protein_preference': proteinPreference,
      'diet_style': dietStyle,
      'checkin_day': checkinDay,
      'onboarding_completed': true,
      'recalculate_targets': true,
    };

    final res = await _dio.put<Map<String, dynamic>>(
      '/api/v1/profile',
      data: payload,
    );
    return UserProfileModel.fromJson(res.data!);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(dioProvider)),
);

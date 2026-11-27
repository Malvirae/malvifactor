import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/profile/data/profile_repository.dart';

class ProfileNotifier extends StateNotifier<AsyncValue<UserProfileModel>> {
  ProfileNotifier(this._ref, this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final Ref _ref;
  final ProfileRepository _repo;

  Future<void> load({bool silent = false}) async {
    if (!silent || !state.hasValue) {
      state = const AsyncValue.loading();
    }
    try {
      final profile = await _repo.fetchProfile();
      state = AsyncValue.data(profile);
    } catch (e, st) {
      if (!silent || !state.hasValue) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void setProfile(UserProfileModel profile) {
    state = AsyncValue.data(profile);
  }

  Future<String?> saveAndRecalculate({
    required String sex,
    required DateTime birthDate,
    required double heightCm,
    required String activityLevel,
    required String goalType,
    required double targetRateKgPerWeek,
    required String proteinPreference,
    required String dietStyle,
    required int checkinDay,
    double? referenceWeightKg,
  }) async {
    try {
      final updated = await _repo.updateProfile(
        sex: sex,
        birthDate: birthDate,
        heightCm: heightCm,
        activityLevel: activityLevel,
        goalType: goalType,
        targetRateKgPerWeek: targetRateKgPerWeek,
        proteinPreference: proteinPreference,
        dietStyle: dietStyle,
        checkinDay: checkinDay,
        recalculateTargets: true,
        referenceWeightKg: referenceWeightKg,
      );
      state = AsyncValue.data(updated);
      _ref.invalidate(dashboardProvider);
      return null;
    } on DioException catch (e) {
      final detail = e.response?.data is Map<String, dynamic>
          ? (e.response?.data['detail'] as String?)
          : null;
      return detail ?? 'Erreur lors de la mise à jour du profil.';
    } catch (_) {
      return 'Erreur inattendue lors de la mise à jour.';
    }
  }
}

final profileProvider =
    StateNotifierProvider<ProfileNotifier, AsyncValue<UserProfileModel>>((ref) {
  final repo = ref.watch(profileRepositoryProvider);
  return ProfileNotifier(ref, repo);
});

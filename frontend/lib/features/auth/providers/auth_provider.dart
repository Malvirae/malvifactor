import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:malvifactor/core/config/server_config_provider.dart';
import 'package:malvifactor/core/network/dio_client.dart';
import 'package:malvifactor/core/services/health_connect_service.dart';
import 'package:malvifactor/features/analytics/presentation/analytics_detail_screen.dart';
import 'package:malvifactor/features/auth/data/auth_repository.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.isLoading = false,
    this.errorMessage,
  });

  const AuthState.unknown()
      : status = AuthStatus.unknown,
        user = null,
        isLoading = false,
        errorMessage = null;

  const AuthState.unauthenticated({this.errorMessage})
      : status = AuthStatus.unauthenticated,
        user = null,
        isLoading = false;

  const AuthState.authenticated(UserModel this.user)
      : status = AuthStatus.authenticated,
        isLoading = false,
        errorMessage = null;

  final AuthStatus status;
  final UserModel? user;
  final bool isLoading;
  final String? errorMessage;

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref, this._repo) : super(const AuthState.unknown()) {
    _ref.listen<int>(sessionExpiredProvider, (_, __) {
      state = const AuthState.unauthenticated(
        errorMessage: 'Session expirée. Veuillez vous reconnecter.',
      );
    });
    restoreSession();
  }

  final Ref _ref;
  final AuthRepository _repo;

  Future<void> restoreSession() async {
    await _ref.read(serverConfigProvider.notifier).load();
    final hasToken = await _repo.hasStoredAccessToken();
    if (!hasToken) {
      state = const AuthState.unauthenticated();
      return;
    }

    try {
      final user = await _repo.fetchCurrentUser();
      state = AuthState.authenticated(user);
      _triggerSilentHealthConnectSync();
    } catch (_) {
      await _repo.clearTokens();
      state = const AuthState.unauthenticated();
    }
  }

  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final user = await _repo.login(
        identifier: identifier,
        password: password,
      );
      state = AuthState.authenticated(user);
      _triggerSilentHealthConnectSync();
      return true;
    } on DioException catch (e) {
      final detail = e.response?.data is Map<String, dynamic>
          ? (e.response?.data['detail'] as String?)
          : null;
      final message = detail ??
          (e.type == DioExceptionType.connectionTimeout ||
                  e.type == DioExceptionType.connectionError
              ? 'Serveur inaccessible. Vérifiez l’URL dans la configuration.'
              : 'Identifiants invalides.');
      state = AuthState.unauthenticated(errorMessage: message);
      return false;
    } catch (_) {
      state = const AuthState.unauthenticated(
        errorMessage: 'Une erreur inattendue est survenue.',
      );
      return false;
    }
  }

  Future<void> logout() async {
    await _repo.clearTokens();
    state = const AuthState.unauthenticated();
  }

  Future<void> _triggerSilentHealthConnectSync() async {
    final hcState = _ref.read(healthConnectProvider);
    if (!hcState.isSupported || !hcState.autoSyncEnabled) return;
    final synced = await _ref
        .read(healthConnectProvider.notifier)
        .syncWeights(interactive: false);
    if (synced) {
      _ref.invalidate(dashboardProvider);
      _ref.invalidate(analyticsSeriesProvider);
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthNotifier(ref, repo);
});

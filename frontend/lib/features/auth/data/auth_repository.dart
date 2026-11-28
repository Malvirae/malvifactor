import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:malvifactor/core/config/server_config_provider.dart';
import 'package:malvifactor/core/network/dio_client.dart';

class UserModel {
  const UserModel({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String username;
  final String displayName;
  final bool isActive;
  final DateTime createdAt;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class AuthRepository {
  AuthRepository({required this.dio, required this.storage});

  final Dio dio;
  final FlutterSecureStorage storage;

  Future<UserModel> login({
    required String identifier,
    required String password,
  }) async {
    final trimmed = identifier.trim();
    final payload = <String, dynamic>{
      if (trimmed.contains('@')) 'email': trimmed else 'username': trimmed,
      'password': password,
    };

    final response = await dio.post<Map<String, dynamic>>(
      '/api/v1/auth/login',
      data: payload,
      options: Options(extra: const {'skipAuth': true}),
    );

    final data = response.data!;
    await storage.write(
      key: accessTokenStorageKey,
      value: data['access_token'] as String,
    );
    await storage.write(
      key: refreshTokenStorageKey,
      value: data['refresh_token'] as String,
    );

    return fetchCurrentUser();
  }

  Future<UserModel> fetchCurrentUser() async {
    final response = await dio.get<Map<String, dynamic>>('/api/v1/auth/me');
    return UserModel.fromJson(response.data!);
  }

  Future<bool> hasStoredAccessToken() async {
    final token = await storage.read(key: accessTokenStorageKey);
    return token != null && token.isNotEmpty;
  }

  Future<void> clearTokens() async {
    await storage.delete(key: accessTokenStorageKey);
    await storage.delete(key: refreshTokenStorageKey);
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    dio: ref.watch(dioProvider),
    storage: ref.watch(secureStorageProvider),
  );
});

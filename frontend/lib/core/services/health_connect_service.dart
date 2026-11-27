import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health/health.dart';

import 'package:malvifactor/core/config/server_config_provider.dart';
import 'package:malvifactor/core/network/dio_client.dart';

const String _hcAutoSyncKey = 'malvifactor_hc_auto_sync';
const String _hcLastSyncKey = 'malvifactor_hc_last_sync';

class HealthConnectState {
  const HealthConnectState({
    required this.isSupported,
    required this.autoSyncEnabled,
    this.isSyncing = false,
    this.lastSyncedAt,
    this.lastSyncedCount,
    this.statusMessage,
  });

  final bool isSupported;
  final bool autoSyncEnabled;
  final bool isSyncing;
  final DateTime? lastSyncedAt;
  final int? lastSyncedCount;
  final String? statusMessage;

  HealthConnectState copyWith({
    bool? autoSyncEnabled,
    bool? isSyncing,
    DateTime? lastSyncedAt,
    int? lastSyncedCount,
    String? statusMessage,
  }) {
    return HealthConnectState(
      isSupported: isSupported,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastSyncedCount: lastSyncedCount ?? this.lastSyncedCount,
      statusMessage: statusMessage,
    );
  }
}

class HealthConnectNotifier extends StateNotifier<HealthConnectState> {
  HealthConnectNotifier(this._dio, this._storage)
      : super(
          HealthConnectState(
            isSupported: !kIsWeb && Platform.isAndroid,
            autoSyncEnabled: true,
          ),
        ) {
    _loadPrefs();
  }

  final Dio _dio;
  final FlutterSecureStorage _storage;

  Future<void> _loadPrefs() async {
    final autoRaw = await _storage.read(key: _hcAutoSyncKey);
    final lastRaw = await _storage.read(key: _hcLastSyncKey);
    state = state.copyWith(
      autoSyncEnabled: autoRaw == null ? true : autoRaw == 'true',
      lastSyncedAt: lastRaw != null ? DateTime.tryParse(lastRaw) : null,
    );
  }

  Future<void> setAutoSync(bool enabled) async {
    state = state.copyWith(autoSyncEnabled: enabled);
    await _storage.write(key: _hcAutoSyncKey, value: enabled.toString());
  }

  Future<(double? weightKg, double? bodyFatPct)> fetchLatestMeasurement() async {
    if (!state.isSupported) return (null, null);
    try {
      final health = Health();
      await health.configure();

      final available = await health.isHealthConnectAvailable();
      if (!available) return (null, null);

      const types = [
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
      ];
      const permissions = [
        HealthDataAccess.READ,
        HealthDataAccess.READ,
      ];

      final hasPerm = await health.hasPermissions(types, permissions: permissions);
      var granted = hasPerm ?? false;
      if (!granted) {
        granted = await health.requestAuthorization(
          types,
          permissions: permissions,
        );
      }
      if (!granted) return (null, null);

      final now = DateTime.now();
      final points = await health.getHealthDataFromTypes(
        startTime: now.subtract(const Duration(days: 30)),
        endTime: now,
        types: types,
      );
      points.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));

      double? latestWeight;
      double? latestFat;
      for (final p in points) {
        final val = p.value;
        if (val is! NumericHealthValue) continue;
        if (p.type == HealthDataType.WEIGHT && latestWeight == null) {
          latestWeight = val.numericValue.toDouble();
        } else if (p.type == HealthDataType.BODY_FAT_PERCENTAGE &&
            latestFat == null) {
          var fat = val.numericValue.toDouble();
          if (fat > 0 && fat <= 1.0) fat = fat * 100.0;
          latestFat = fat;
        }
        if (latestWeight != null && latestFat != null) break;
      }
      return (latestWeight, latestFat);
    } catch (_) {
      return (null, null);
    }
  }

  Future<bool> syncWeights({bool interactive = false}) async {
    if (!state.isSupported) {
      if (interactive) {
        state = state.copyWith(
          statusMessage: 'Health Connect est disponible uniquement sur Android.',
        );
      }
      return false;
    }
    if (state.isSyncing) return false;

    state = state.copyWith(isSyncing: true, statusMessage: null);
    try {
      final health = Health();
      await health.configure();

      final sdkStatus = await health.getHealthConnectSdkStatus();
      if (sdkStatus != HealthConnectSdkStatus.sdkAvailable) {
        state = state.copyWith(
          isSyncing: false,
          statusMessage: interactive
              ? (sdkStatus ==
                      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired
                  ? 'Health Connect nécessite une mise à jour via le Play Store.'
                  : 'Health Connect n’est pas disponible sur cet appareil.')
              : null,
        );
        return false;
      }

      const types = [
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
      ];
      const permissions = [
        HealthDataAccess.READ,
        HealthDataAccess.READ,
      ];

      final hasPerm = await health.hasPermissions(types, permissions: permissions);
      var granted = hasPerm ?? false;
      if (!granted && interactive) {
        granted = await health.requestAuthorization(
          types,
          permissions: permissions,
        );
      }
      if (!granted) {
        state = state.copyWith(
          isSyncing: false,
          statusMessage: interactive
              ? 'Autorisation Health Connect refusée.'
              : null,
        );
        return false;
      }

      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 14));
      final points = await health.getHealthDataFromTypes(
        startTime: start,
        endTime: now,
        types: types,
      );

      final Map<String, Map<String, dynamic>> grouped = {};
      for (final point in points) {
        final val = point.value;
        if (val is! NumericHealthValue) continue;

        final dt = point.dateFrom.toUtc();
        final key =
            '${dt.year}-${dt.month}-${dt.day}T${dt.hour}:${dt.minute}';
        final entry = grouped.putIfAbsent(
          key,
          () => <String, dynamic>{
            'measured_at': dt.toIso8601String(),
          },
        );

        if (point.type == HealthDataType.WEIGHT) {
          entry['weight_kg'] = val.numericValue.toDouble();
        } else if (point.type == HealthDataType.BODY_FAT_PERCENTAGE) {
          var fatPct = val.numericValue.toDouble();
          if (fatPct > 0 && fatPct <= 1.0) {
            fatPct = fatPct * 100.0;
          }
          entry['body_fat_pct'] = fatPct;
        }
      }

      final items = grouped.values
          .where((item) => item['weight_kg'] != null)
          .toList();

      if (items.isEmpty) {
        final syncedAt = DateTime.now();
        await _storage.write(
          key: _hcLastSyncKey,
          value: syncedAt.toIso8601String(),
        );
        state = state.copyWith(
          isSyncing: false,
          lastSyncedAt: syncedAt,
          lastSyncedCount: 0,
          statusMessage: interactive ? 'Aucune nouvelle pesée trouvée.' : null,
        );
        return false;
      }

      await _dio.post<Map<String, dynamic>>(
        '/api/v1/weights/sync',
        data: {'items': items},
      );

      final syncedAt = DateTime.now();
      await _storage.write(
        key: _hcLastSyncKey,
        value: syncedAt.toIso8601String(),
      );
      state = state.copyWith(
        isSyncing: false,
        lastSyncedAt: syncedAt,
        lastSyncedCount: items.length,
        statusMessage: '${items.length} pesée(s) synchronisée(s).',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        statusMessage: interactive ? 'Erreur Health Connect : $e' : null,
      );
      return false;
    }
  }
}

final healthConnectProvider =
    StateNotifierProvider<HealthConnectNotifier, HealthConnectState>((ref) {
  return HealthConnectNotifier(
    ref.watch(dioProvider),
    ref.watch(secureStorageProvider),
  );
});

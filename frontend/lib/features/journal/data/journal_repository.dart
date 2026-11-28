import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:malvifactor/core/network/dio_client.dart';

class JournalRepository {
  JournalRepository(this._dio);

  final Dio _dio;

  String _formatTime(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm:00';
  }

  Future<void> updateLog({
    required String logId,
    double? quantityG,
    TimeOfDay? loggedTime,
    String? foodId,
    String? customName,
    double? kcal,
    double? proteinG,
    double? fatG,
    double? carbsG,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '/api/v1/logs/$logId',
      data: {
        if (quantityG != null) 'quantity_g': quantityG,
        if (loggedTime != null) 'logged_time': _formatTime(loggedTime),
        if (foodId != null) 'food_id': foodId,
        if (customName != null) 'custom_name': customName,
        if (kcal != null) 'kcal': kcal,
        if (proteinG != null) 'protein_g': proteinG,
        if (fatG != null) 'fat_g': fatG,
        if (carbsG != null) 'carbs_g': carbsG,
      },
    );
  }

  Future<void> deleteLog(String logId) async {
    await _dio.delete<void>('/api/v1/logs/$logId');
  }

  Future<void> copyDay({
    required DateTime sourceDate,
    required DateTime targetDate,
  }) async {
    await _dio.post<List<dynamic>>(
      '/api/v1/logs/copy',
      data: {
        'source_date': DateFormat('yyyy-MM-dd').format(sourceDate),
        'target_date': DateFormat('yyyy-MM-dd').format(targetDate),
      },
    );
  }

  Future<void> copyLogIds({
    required List<String> logIds,
    required DateTime targetDate,
    TimeOfDay? targetTime,
  }) async {
    await _dio.post<List<dynamic>>(
      '/api/v1/logs/copy',
      data: {
        'log_ids': logIds,
        'target_date': DateFormat('yyyy-MM-dd').format(targetDate),
        if (targetTime != null) 'target_time': _formatTime(targetTime),
      },
    );
  }

  Future<void> moveLogIds({
    required List<String> logIds,
    required DateTime targetDate,
    TimeOfDay? targetTime,
  }) async {
    await _dio.post<List<dynamic>>(
      '/api/v1/logs/move',
      data: {
        'log_ids': logIds,
        'target_date': DateFormat('yyyy-MM-dd').format(targetDate),
        if (targetTime != null) 'target_time': _formatTime(targetTime),
      },
    );
  }

  Future<void> batchDeleteLogs(List<String> logIds) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/logs/batch-delete',
      data: {'log_ids': logIds},
    );
  }
}

final journalRepositoryProvider = Provider<JournalRepository>(
  (ref) => JournalRepository(ref.watch(dioProvider)),
);

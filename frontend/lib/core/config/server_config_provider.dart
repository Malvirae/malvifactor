import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String _localFallbackUrl = 'http://192.168.1.251:8086';
const String _productionServerUrl = 'https://macro.etixel.com';
const String _serverUrlStorageKey = 'malvifactor_server_url';

String resolveDefaultServerUrl() {
  if (kIsWeb) {
    final host = Uri.base.host.toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1' || host.isEmpty) {
      return _localFallbackUrl;
    }
    return Uri.base.origin;
  }
  return _productionServerUrl;
}

final String defaultServerUrl = resolveDefaultServerUrl();

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

class ServerConfigNotifier extends StateNotifier<String> {
  ServerConfigNotifier(this._storage) : super(resolveDefaultServerUrl());

  final FlutterSecureStorage _storage;

  Future<void> load() async {
    final saved = await _storage.read(key: _serverUrlStorageKey);
    if (saved != null && saved.trim().isNotEmpty) {
      state = _normalizeUrl(saved);
    } else {
      state = resolveDefaultServerUrl();
    }
  }

  Future<void> setServerUrl(String url) async {
    final normalized = _normalizeUrl(url);
    state = normalized;
    await _storage.write(key: _serverUrlStorageKey, value: normalized);
  }

  String _normalizeUrl(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.isEmpty ? resolveDefaultServerUrl() : trimmed;
  }
}

final serverConfigProvider =
    StateNotifierProvider<ServerConfigNotifier, String>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return ServerConfigNotifier(storage);
});

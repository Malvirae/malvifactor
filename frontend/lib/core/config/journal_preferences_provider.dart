import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:malvifactor/core/config/server_config_provider.dart';

const String _journalCompactModeKey = 'malvifactor_journal_compact_mode';

class JournalCompactModeNotifier extends StateNotifier<bool> {
  JournalCompactModeNotifier(this._storage) : super(false) {
    _load();
  }

  final FlutterSecureStorage _storage;

  Future<void> _load() async {
    final raw = await _storage.read(key: _journalCompactModeKey);
    if (raw != null) {
      state = raw == 'true';
    }
  }

  Future<void> setCompactMode(bool enabled) async {
    state = enabled;
    await _storage.write(
      key: _journalCompactModeKey,
      value: enabled.toString(),
    );
  }
}

final journalCompactModeProvider =
    StateNotifierProvider<JournalCompactModeNotifier, bool>((ref) {
  return JournalCompactModeNotifier(ref.watch(secureStorageProvider));
});

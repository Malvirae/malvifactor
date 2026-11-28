import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/config/server_config_provider.dart';
import 'package:malvifactor/core/theme/app_theme.dart';

class NetworkServerScreen extends ConsumerStatefulWidget {
  const NetworkServerScreen({super.key});

  @override
  ConsumerState<NetworkServerScreen> createState() =>
      _NetworkServerScreenState();
}

class _NetworkServerScreenState extends ConsumerState<NetworkServerScreen> {
  late final TextEditingController _urlController;
  bool _testing = false;
  bool? _isOnline;
  int? _latencyMs;
  String? _statusDetail;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: ref.read(serverConfigProvider),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _testConnection();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final raw = _urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (raw.isEmpty) return;

    setState(() {
      _testing = true;
      _statusDetail = null;
    });

    final sw = Stopwatch()..start();
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: raw,
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );
      final res = await dio.get<Map<String, dynamic>>('/api/health');
      sw.stop();
      if (!mounted) return;
      final ok = res.statusCode == 200 && res.data?['status'] == 'ok';
      setState(() {
        _testing = false;
        _isOnline = ok;
        _latencyMs = sw.elapsedMilliseconds;
        _statusDetail = ok
            ? 'Serveur et base PostgreSQL opérationnels'
            : 'Réponse inattendue (${res.statusCode})';
      });
    } on DioException catch (e) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _isOnline = false;
        _latencyMs = null;
        _statusDetail = e.message ?? 'Serveur inaccessible';
      });
    } catch (e) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _isOnline = false;
        _latencyMs = null;
        _statusDetail = 'Erreur : $e';
      });
    }
  }

  Future<void> _saveUrl() async {
    final clean = _urlController.text.trim();
    if (clean.isEmpty) return;
    await ref.read(serverConfigProvider.notifier).setServerUrl(clean);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('URL du serveur enregistrée.'),
        backgroundColor: AppColors.success,
      ),
    );
    await _testConnection();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _isOnline == true
        ? AppColors.carbs
        : (_isOnline == false ? AppColors.error : AppColors.textMuted);
    final statusLabel = _testing
        ? 'Vérification...'
        : (_isOnline == true
            ? 'Connecté${_latencyMs != null ? ' · $_latencyMs ms' : ''}'
            : (_isOnline == false ? 'Hors ligne' : 'Non vérifié'));

    return Scaffold(
      appBar: AppBar(title: const Text('Réseau & Serveur')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            decoration: AppTheme.matteCardDecoration(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        statusLabel,
                        style: AppTheme.numericStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.calories,
                              ),
                            )
                          : const Icon(LucideIcons.activity, size: 16),
                      label: const Text('Tester'),
                    ),
                  ],
                ),
                if (_statusDetail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _statusDetail!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: AppTheme.matteCardDecoration(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Adresse du backend FastAPI',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'URL du backend',
                    prefixIcon: Icon(LucideIcons.globe, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Local (:8086)'),
                      onPressed: () {
                        _urlController.text = 'http://192.168.1.251:8086';
                        setState(() {});
                      },
                    ),
                    ActionChip(
                      label: const Text('Tunnel HTTPS'),
                      onPressed: () {
                        _urlController.text = 'https://macro.etixel.com';
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(LucideIcons.wifi, size: 16),
                        label: const Text('Tester la connexion'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveUrl,
                        icon: const Icon(LucideIcons.save, size: 16),
                        label: const Text('Enregistrer'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

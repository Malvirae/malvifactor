import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:malvifactor/core/theme/app_theme.dart';

const String _githubLatestReleaseUrl =
    'https://api.github.com/repos/Malvirae/malvifactor/releases/latest';
const String _githubOtaToken = String.fromEnvironment('GITHUB_OTA_TOKEN');

class OtaReleaseInfo {
  const OtaReleaseInfo({
    required this.version,
    required this.tagName,
    required this.releaseNotes,
    required this.apkUrl,
    required this.apkName,
  });

  final String version;
  final String tagName;
  final String releaseNotes;
  final String apkUrl;
  final String apkName;
}

class OtaUpdateService {
  const OtaUpdateService._();

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  static bool _isNewerVersion(String remote, String current) {
    List<int> parseParts(String v) => v
        .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
        .split('+')
        .first
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();

    final r = parseParts(remote);
    final c = parseParts(current);
    final len = r.length > c.length ? r.length : c.length;
    for (var i = 0; i < len; i++) {
      final rv = i < r.length ? r[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (rv > cv) return true;
      if (rv < cv) return false;
    }
    return false;
  }

  static Future<OtaReleaseInfo?> checkForUpdate() async {
    if (!isSupported) return null;

    final currentVersion = await getCurrentVersion();
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      if (_githubOtaToken.isNotEmpty)
        'Authorization': 'Bearer $_githubOtaToken',
    };

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: headers,
      ),
    );

    final Response<Map<String, dynamic>> res;
    try {
      res = await dio.get<Map<String, dynamic>>(_githubLatestReleaseUrl);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
    final data = res.data;
    if (data == null) return null;

    final tagName = (data['tag_name'] as String?) ?? '';
    final cleanVersion =
        tagName.replaceFirst(RegExp(r'^v', caseSensitive: false), '');
    if (cleanVersion.isEmpty || !_isNewerVersion(cleanVersion, currentVersion)) {
      return null;
    }

    final assets = data['assets'] as List<dynamic>? ?? const [];
    String? apkUrl;
    String? apkName;
    for (final rawAsset in assets) {
      final asset = rawAsset as Map<String, dynamic>;
      final name = (asset['name'] as String?) ?? '';
      if (name.toLowerCase().endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        apkName = name;
        break;
      }
    }
    if (apkUrl == null || apkName == null) return null;

    return OtaReleaseInfo(
      version: cleanVersion,
      tagName: tagName,
      releaseNotes: (data['body'] as String?)?.trim() ?? '',
      apkUrl: apkUrl,
      apkName: apkName,
    );
  }

  static Future<void> checkAndPrompt(
    BuildContext context, {
    bool showUpToDateMessage = false,
  }) async {
    if (!isSupported) {
      if (showUpToDateMessage && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Les mises à jour OTA sont réservées à Android.'),
            backgroundColor: AppColors.surfaceElevated,
          ),
        );
      }
      return;
    }

    try {
      final release = await checkForUpdate();
      if (!context.mounted) return;
      if (release == null) {
        if (showUpToDateMessage) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Votre application est déjà à jour.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OtaUpdateDialog(release: release),
      );
    } catch (e) {
      if (showUpToDateMessage && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossible de vérifier les mises à jour : $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

class _OtaUpdateDialog extends StatefulWidget {
  const _OtaUpdateDialog({required this.release});

  final OtaReleaseInfo release;

  @override
  State<_OtaUpdateDialog> createState() => _OtaUpdateDialogState();
}

class _OtaUpdateDialogState extends State<_OtaUpdateDialog> {
  bool _downloading = false;
  double _progress = 0.0;
  String? _error;

  Future<void> _downloadAndInstall() async {
    setState(() {
      _downloading = true;
      _progress = 0.0;
      _error = null;
    });

    try {
      final cacheDir = await getTemporaryDirectory();
      final targetPath = '${cacheDir.path}/${widget.release.apkName}';

      final dio = Dio(
        BaseOptions(
          headers: {
            if (_githubOtaToken.isNotEmpty)
              'Authorization': 'Bearer $_githubOtaToken',
          },
        ),
      );

      await dio.download(
        widget.release.apkUrl,
        targetPath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );

      final result = await OpenFilex.open(
        targetPath,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done && mounted) {
        setState(() {
          _downloading = false;
          _error = 'Ouverture de l’installateur impossible : ${result.message}';
        });
      } else if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'Échec du téléchargement : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_progress * 100).round();
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Mise à jour ${widget.release.tagName} disponible'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.release.releaseNotes.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Text(
                  widget.release.releaseNotes,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            const Text(
              'Une nouvelle version de MalviFactor est prête à être installée.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              color: AppColors.calories,
              backgroundColor: AppColors.surfaceElevated,
            ),
            const SizedBox(height: 6),
            Text(
              'Téléchargement : $pct %',
              textAlign: TextAlign.center,
              style: AppTheme.numericStyle(
                fontSize: 12,
                color: AppColors.calories,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ],
        ],
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Plus tard'),
          ),
        ElevatedButton(
          onPressed: _downloading ? null : _downloadAndInstall,
          child: Text(_downloading ? 'Téléchargement...' : 'Installer'),
        ),
      ],
    );
  }
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:malvifactor/core/network/dio_client.dart';
import 'package:malvifactor/core/services/ota_update_service.dart';
import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/food_logger/providers/food_basket_provider.dart';
import 'package:malvifactor/features/journal/presentation/journal_screen.dart';
import 'package:malvifactor/features/recipes/data/recipe_repository.dart';

class AboutUpdatesScreen extends ConsumerStatefulWidget {
  const AboutUpdatesScreen({super.key});

  @override
  ConsumerState<AboutUpdatesScreen> createState() => _AboutUpdatesScreenState();
}

class _AboutUpdatesScreenState extends ConsumerState<AboutUpdatesScreen> {
  bool _checkingUpdate = false;

  String get _platformLabel {
    if (kIsWeb) return 'Web PWA';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    return 'Linux';
  }

  Future<void> _openChangePasswordDialog() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? errorText;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Changer le mot de passe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: currentCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe actuel',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nouveau mot de passe (min. 8 car.)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmer le nouveau mot de passe',
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorText!,
                  style: const TextStyle(fontSize: 12, color: AppColors.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final current = currentCtrl.text;
                      final next = newCtrl.text;
                      final confirm = confirmCtrl.text;
                      if (current.isEmpty) {
                        setModalState(
                          () => errorText = 'Saisissez votre mot de passe actuel.',
                        );
                        return;
                      }
                      if (next.length < 8) {
                        setModalState(
                          () => errorText = 'Minimum 8 caractères requis.',
                        );
                        return;
                      }
                      if (next != confirm) {
                        setModalState(
                          () => errorText = 'Les mots de passe ne correspondent pas.',
                        );
                        return;
                      }

                      setModalState(() {
                        isSaving = true;
                        errorText = null;
                      });

                      try {
                        await ref.read(dioProvider).post<Map<String, dynamic>>(
                          '/api/v1/auth/change-password',
                          data: {
                            'current_password': current,
                            'new_password': next,
                          },
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Mot de passe mis à jour.'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } on DioException catch (e) {
                        final detail = (e.response?.data is Map)
                            ? (e.response?.data['detail']?.toString() ?? '')
                            : '';
                        setModalState(() {
                          isSaving = false;
                          errorText = detail.isNotEmpty
                              ? detail
                              : 'Impossible de modifier le mot de passe.';
                        });
                      } catch (_) {
                        setModalState(() {
                          isSaving = false;
                          errorText = 'Erreur lors du changement de mot de passe.';
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.background,
                      ),
                    )
                  : const Text('Mettre à jour'),
            ),
          ],
        ),
      ),
    );
  }

  void _refreshLocalCache() {
    ref.invalidate(dashboardProvider);
    ref.invalidate(journalDayProvider);
    ref.invalidate(fullMetricContextProvider);
    ref.invalidate(recipesListProvider);
    ref.invalidate(foodSuggestionsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cache local rafraîchi.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mises à jour & À propos')),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final version = snapshot.data?.version ?? '1.3.0';
          final buildNumber = snapshot.data?.buildNumber ?? '17';

          return ListView(
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
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.calories.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            LucideIcons.sparkles,
                            color: AppColors.calories,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'MalviFactor',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'v$version (build $buildNumber) · $_platformLabel',
                                style: AppTheme.numericStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _checkingUpdate
                          ? null
                          : () async {
                              setState(() => _checkingUpdate = true);
                              await OtaUpdateService.checkAndPrompt(
                                context,
                                showUpToDateMessage: true,
                              );
                              if (mounted) {
                                setState(() => _checkingUpdate = false);
                              }
                            },
                      icon: _checkingUpdate
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.background,
                              ),
                            )
                          : const Icon(LucideIcons.download, size: 17),
                      label: const Text('Vérifier les mises à jour'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: AppTheme.matteCardDecoration(),
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.weight.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          LucideIcons.keyRound,
                          size: 17,
                          color: AppColors.weight,
                        ),
                      ),
                      title: const Text(
                        'Changer le mot de passe',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Mettre à jour votre mot de passe de connexion',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      trailing: const Icon(
                        LucideIcons.chevronRight,
                        size: 17,
                        color: AppColors.textMuted,
                      ),
                      onTap: _openChangePasswordDialog,
                    ),
                    const Divider(
                      height: 1,
                      thickness: 0.6,
                      color: Colors.white10,
                    ),
                    ListTile(
                      leading: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.calories.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          LucideIcons.refreshCw,
                          size: 17,
                          color: AppColors.calories,
                        ),
                      ),
                      title: const Text(
                        'Rafraîchir le cache local',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Force le rechargement du dashboard, journal et suggestions',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      trailing: const Icon(
                        LucideIcons.chevronRight,
                        size: 17,
                        color: AppColors.textMuted,
                      ),
                      onTap: _refreshLocalCache,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/config/journal_preferences_provider.dart';
import 'package:malvifactor/core/config/server_config_provider.dart';
import 'package:malvifactor/core/network/dio_client.dart';
import 'package:malvifactor/core/services/health_connect_service.dart';
import 'package:malvifactor/core/services/ota_update_service.dart';
import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/presentation/analytics_detail_screen.dart';
import 'package:malvifactor/features/auth/providers/auth_provider.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/journal/presentation/journal_screen.dart';
import 'package:malvifactor/features/more/presentation/custom_foods_screen.dart';
import 'package:malvifactor/features/profile/presentation/profile_screen.dart';
import 'package:malvifactor/features/profile/providers/profile_provider.dart';
import 'package:malvifactor/features/recipes/data/recipe_repository.dart';
import 'package:malvifactor/features/recipes/presentation/recipes_list_screen.dart';
import 'package:malvifactor/shared/widgets/weight_entry_dialog.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'MF';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _openServerConfigDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ctrl = TextEditingController(text: ref.read(serverConfigProvider));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Configuration serveur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'URL du backend'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Local (:8086)'),
                  onPressed: () => ctrl.text = 'http://192.168.1.251:8086',
                ),
                ActionChip(
                  label: const Text('Tunnel HTTPS'),
                  onPressed: () => ctrl.text = 'https://macro.etixel.com',
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(serverConfigProvider.notifier)
                  .setServerUrl(ctrl.text);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmResetData(
    BuildContext context,
    WidgetRef ref,
  ) async {
    var isResetting = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Réinitialiser mes données'),
          content: const Text(
            'Cette action supprimera définitivement votre journal alimentaire, vos pesées, vos bilans, vos recettes et vos aliments personnalisés, puis relancera l’onboarding.\n\nVotre compte et vos identifiants de connexion seront conservés.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: isResetting ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: isResetting
                  ? null
                  : () async {
                      setState(() => isResetting = true);
                      try {
                        await ref
                            .read(dioProvider)
                            .post<Map<String, dynamic>>('/api/v1/profile/reset-data');
                        ref.invalidate(profileProvider);
                        ref.invalidate(dashboardProvider);
                        ref.invalidate(journalDayProvider);
                        ref.invalidate(analyticsSeriesProvider);
                        ref.invalidate(recipesListProvider);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (context.mounted) context.go('/onboarding');
                      } catch (_) {
                        setState(() => isResetting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Impossible de réinitialiser les données.'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
              child: isResetting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textPrimary,
                      ),
                    )
                  : const Text('Réinitialiser'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChangePasswordDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? errorText;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.error,
                  ),
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
                        setState(() => errorText = 'Saisissez votre mot de passe actuel.');
                        return;
                      }
                      if (next.length < 8) {
                        setState(() => errorText = 'Minimum 8 caractères requis.');
                        return;
                      }
                      if (next != confirm) {
                        setState(() => errorText = 'Les mots de passe ne correspondent pas.');
                        return;
                      }

                      setState(() {
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
                        if (context.mounted) {
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
                        setState(() {
                          isSaving = false;
                          errorText = detail.isNotEmpty
                              ? detail
                              : 'Impossible de modifier le mot de passe.';
                        });
                      } catch (_) {
                        setState(() {
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

  Future<void> _openHealthConnectSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final hc = ref.watch(healthConnectProvider);
          final lastSyncText = hc.lastSyncedAt != null
              ? DateFormat('dd/MM/yyyy HH:mm').format(hc.lastSyncedAt!)
              : 'Jamais synchronisé';

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Google Health Connect',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  hc.isSupported
                      ? 'Dernière synchro : $lastSyncText'
                      : 'Disponible uniquement sur Android.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (hc.statusMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    hc.statusMessage!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.calories,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Synchro automatique au démarrage'),
                  value: hc.autoSyncEnabled,
                  activeTrackColor: AppColors.calories,
                  onChanged: (val) =>
                      ref.read(healthConnectProvider.notifier).setAutoSync(val),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: hc.isSyncing
                      ? null
                      : () async {
                          final ok = await ref
                              .read(healthConnectProvider.notifier)
                              .syncWeights(interactive: true);
                          if (ok) {
                            ref.invalidate(dashboardProvider);
                            ref.invalidate(analyticsSeriesProvider);
                          }
                        },
                  icon: hc.isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.background,
                          ),
                        )
                      : const Icon(LucideIcons.refreshCw, size: 18),
                  label: const Text('Synchroniser maintenant'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final serverUrl = ref.watch(serverConfigProvider);
    final hc = ref.watch(healthConnectProvider);
    final isCompactJournal = ref.watch(journalCompactModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PLUS',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.textPrimary,
                child: Text(
                  _initials(user?.displayName ?? 'MF'),
                  style: const TextStyle(
                    color: AppColors.background,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? 'Utilisateur',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Nutrition & Données',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _MoreTile(
                  icon: LucideIcons.chefHat,
                  title: 'Mes Recettes partagées',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RecipesListScreen(),
                    ),
                  ),
                ),
                const Divider(),
                _MoreTile(
                  icon: LucideIcons.plusCircle,
                  title: 'Aliments personnalisés',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CustomFoodsScreen(),
                    ),
                  ),
                ),
                const Divider(),
                _MoreTile(
                  icon: LucideIcons.scale,
                  title: 'Ajouter une pesée',
                  onTap: () => showManualWeightDialog(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Général & Intégrations',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _MoreTile(
                  icon: LucideIcons.refreshCw,
                  title: 'Health Connect',
                  subtitle: hc.isSupported
                      ? (hc.lastSyncedAt != null
                          ? 'Dernière synchro : ${DateFormat('dd/MM HH:mm').format(hc.lastSyncedAt!)}'
                          : 'Prêt sur Android')
                      : 'Android uniquement',
                  onTap: () => _openHealthConnectSheet(context, ref),
                ),
                const Divider(),
                _MoreTile(
                  icon: LucideIcons.userCog,
                  title: 'Profil physiologique',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
              builder: (_) => const ProfileScreen(
                mode: ProfileEditMode.physiological,
              ),
            ),
                  ),
                ),
                const Divider(),
                _MoreTile(
                  icon: LucideIcons.sparkles,
                  title: 'Relancer l’assistant d’initialisation',
                  onTap: () => context.push('/onboarding'),
                ),
                const Divider(),
                SwitchListTile(
                  value: isCompactJournal,
                  activeTrackColor: AppColors.calories,
                  secondary: const Icon(
                    LucideIcons.rows3,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                  title: const Text(
                    'Mode compact du journal',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: const Text(
                    'Affiche davantage d’aliments simultanément à l’écran',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  onChanged: (val) => ref
                      .read(journalCompactModeProvider.notifier)
                      .setCompactMode(val),
                ),
                const Divider(),
                _MoreTile(
                  icon: LucideIcons.server,
                  title: 'Configuration serveur',
                  subtitle: serverUrl,
                  onTap: () => _openServerConfigDialog(context, ref),
                ),
                const Divider(),
                FutureBuilder<String>(
                  future: OtaUpdateService.getCurrentVersion(),
                  builder: (context, snapshot) {
                    final version = snapshot.data ?? '1.0.0';
                    return _MoreTile(
                      icon: LucideIcons.download,
                      title: 'Rechercher une mise à jour',
                      subtitle: 'Version actuelle : v$version',
                      onTap: () => OtaUpdateService.checkAndPrompt(
                        context,
                        showUpToDateMessage: true,
                      ),
                    );
                  },
                ),
                const Divider(),
                _MoreTile(
                  icon: LucideIcons.keyRound,
                  title: 'Changer le mot de passe',
                  onTap: () => _openChangePasswordDialog(context, ref),
                ),
                const Divider(),
                _MoreTile(
                  icon: LucideIcons.rotateCcw,
                  title: 'Réinitialiser mes données',
                  titleColor: AppColors.warning,
                  iconColor: AppColors.warning,
                  onTap: () => _confirmResetData(context, ref),
                ),
                const Divider(),
                _MoreTile(
                  icon: LucideIcons.logOut,
                  title: 'Se déconnecter',
                  titleColor: AppColors.error,
                  iconColor: AppColors.error,
                  onTap: () => ref.read(authProvider.notifier).logout(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Color? iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        icon,
        size: 20,
        color: iconColor ?? AppColors.textPrimary,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: titleColor ?? AppColors.textPrimary,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            )
          : null,
      trailing: const Icon(
        LucideIcons.chevronRight,
        size: 17,
        color: AppColors.textMuted,
      ),
    );
  }
}

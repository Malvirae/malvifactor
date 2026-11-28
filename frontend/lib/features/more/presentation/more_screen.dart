import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/config/server_config_provider.dart';
import 'package:malvifactor/core/services/health_connect_service.dart';
import 'package:malvifactor/core/services/ota_update_service.dart';
import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/core/widgets/pressable_scale.dart';
import 'package:malvifactor/features/auth/providers/auth_provider.dart';
import 'package:malvifactor/features/more/presentation/about_updates_screen.dart';
import 'package:malvifactor/features/more/presentation/custom_foods_screen.dart';
import 'package:malvifactor/features/more/presentation/health_sync_screen.dart';
import 'package:malvifactor/features/more/presentation/network_server_screen.dart';
import 'package:malvifactor/features/profile/presentation/profile_screen.dart';
import 'package:malvifactor/features/recipes/presentation/recipes_list_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'MF';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _shortHost(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Vous devrez saisir vos identifiants pour vous reconnecter à votre compte.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final serverUrl = ref.watch(serverConfigProvider);
    final hc = ref.watch(healthConnectProvider);

    final healthSubtitle = hc.isSupported
        ? (hc.lastSyncedAt != null
            ? 'Synchro : ${DateFormat('dd/MM HH:mm').format(hc.lastSyncedAt!)}'
            : 'Health Connect prêt')
        : 'Pesées & réinitialisation';

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
      body: FutureBuilder<String>(
        future: OtaUpdateService.getCurrentVersion(),
        builder: (context, versionSnap) {
          final version = versionSnap.data ?? '1.3.2';

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
            children: [
              // 1. Account Header
              Container(
                decoration: AppTheme.matteCardDecoration(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.textPrimary,
                      child: Text(
                        _initials(user?.displayName ?? 'MF'),
                        style: const TextStyle(
                          color: AppColors.background,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? 'Utilisateur',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            user?.email ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.calories.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.calories.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'v$version',
                        style: AppTheme.numericStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.calories,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const _HubSectionLabel('Mon profil & Bibliothèque'),
              _HubCard(
                children: [
                  _MoreHubRow(
                    icon: LucideIcons.userCog,
                    tintColor: AppColors.calories,
                    title: 'Profil physiologique',
                    subtitle: 'Biométrie, taille, âge et niveau d’activité',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProfileScreen(
                          mode: ProfileEditMode.physiological,
                        ),
                      ),
                    ),
                  ),
                  _MoreHubRow(
                    icon: LucideIcons.bookmark,
                    tintColor: AppColors.weight,
                    title: 'Mes aliments personnalisés',
                    subtitle: 'Produits créés et scans corrigés',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CustomFoodsScreen(),
                      ),
                    ),
                  ),
                  _MoreHubRow(
                    icon: LucideIcons.chefHat,
                    tintColor: const Color(0xFF22D3EE),
                    title: 'Recettes partagées',
                    subtitle: 'Plats maison et portions personnalisées',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RecipesListScreen(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const _HubSectionLabel('Données & Synchronisation'),
              _HubCard(
                children: [
                  _MoreHubRow(
                    icon: LucideIcons.heartPulse,
                    tintColor: AppColors.carbs,
                    title: 'Santé & Synchronisation',
                    subtitle: healthSubtitle,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HealthSyncScreen(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const _HubSectionLabel('Application & Système'),
              _HubCard(
                children: [
                  _MoreHubRow(
                    icon: LucideIcons.server,
                    tintColor: AppColors.protein,
                    title: 'Réseau & Serveur',
                    subtitle: _shortHost(serverUrl),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NetworkServerScreen(),
                      ),
                    ),
                  ),
                  _MoreHubRow(
                    icon: LucideIcons.download,
                    tintColor: AppColors.calories,
                    title: 'Mises à jour & À propos',
                    subtitle: 'Version v$version · Sécurité & cache',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AboutUpdatesScreen(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),
              PressableScale(
                onTap: () => _confirmLogout(context, ref),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.logOut,
                        size: 16,
                        color: AppColors.error,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Se déconnecter',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HubSectionLabel extends StatelessWidget {
  const _HubSectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 0.6,
                color: Colors.white10,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _MoreHubRow extends StatelessWidget {
  const _MoreHubRow({
    required this.icon,
    required this.tintColor,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color tintColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tintColor.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: tintColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 1.5),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

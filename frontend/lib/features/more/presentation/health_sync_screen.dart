import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/network/dio_client.dart';
import 'package:malvifactor/core/services/health_connect_service.dart';
import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/food_logger/providers/food_basket_provider.dart';
import 'package:malvifactor/features/journal/presentation/journal_screen.dart';
import 'package:malvifactor/features/profile/providers/profile_provider.dart';
import 'package:malvifactor/features/recipes/data/recipe_repository.dart';
import 'package:malvifactor/shared/widgets/weight_entry_dialog.dart';

class HealthSyncScreen extends ConsumerWidget {
  const HealthSyncScreen({super.key});

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
                            .post<Map<String, dynamic>>(
                              '/api/v1/profile/reset-data',
                            );
                        ref.invalidate(profileProvider);
                        ref.invalidate(dashboardProvider);
                        ref.invalidate(journalDayProvider);
                        ref.invalidate(fullMetricContextProvider);
                        ref.invalidate(recipesListProvider);
                        ref.invalidate(foodSuggestionsProvider);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (context.mounted) context.go('/onboarding');
                      } catch (_) {
                        setState(() => isResetting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Impossible de réinitialiser les données.',
                              ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = ref.watch(healthConnectProvider);
    final lastSyncText = hc.lastSyncedAt != null
        ? DateFormat('dd/MM/yyyy à HH:mm').format(hc.lastSyncedAt!)
        : 'Jamais synchronisé';

    return Scaffold(
      appBar: AppBar(title: const Text('Santé & Synchronisation')),
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.carbs.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        LucideIcons.heartPulse,
                        color: AppColors.carbs,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Google Health Connect',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hc.isSupported
                                ? 'Dernière synchro : $lastSyncText'
                                : 'Disponible uniquement sur Android',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (hc.statusMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.calories.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.calories.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      hc.statusMessage!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.calories,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1, thickness: 0.6, color: Colors.white10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Synchro automatique au démarrage',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Importe automatiquement vos nouvelles pesées et masse grasse',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  value: hc.autoSyncEnabled,
                  activeTrackColor: AppColors.calories,
                  onChanged: hc.isSupported
                      ? (val) => ref
                          .read(healthConnectProvider.notifier)
                          .setAutoSync(val)
                      : null,
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: !hc.isSupported || hc.isSyncing
                      ? null
                      : () async {
                          final ok = await ref
                              .read(healthConnectProvider.notifier)
                              .syncWeights(interactive: true);
                          if (ok) {
                            ref.invalidate(dashboardProvider);
                            ref.invalidate(fullMetricContextProvider);
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
                      : const Icon(LucideIcons.refreshCw, size: 17),
                  label: const Text('Synchroniser maintenant'),
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
                      LucideIcons.scale,
                      size: 17,
                      color: AppColors.weight,
                    ),
                  ),
                  title: const Text(
                    'Saisir une pesée manuelle',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Poids brut et pourcentage de masse grasse',
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
                  onTap: () => showManualWeightDialog(context, ref),
                ),
                const Divider(height: 1, thickness: 0.6, color: Colors.white10),
                ListTile(
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.calories.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      LucideIcons.sparkles,
                      size: 17,
                      color: AppColors.calories,
                    ),
                  ),
                  title: const Text(
                    'Relancer l’assistant d’initialisation',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Recalibrer votre objectif et vos cibles initiales',
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
                  onTap: () => context.push('/onboarding'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Zone de réinitialisation',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Container(
            decoration: AppTheme.matteCardDecoration(),
            child: ListTile(
              leading: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  LucideIcons.rotateCcw,
                  size: 17,
                  color: AppColors.warning,
                ),
              ),
              title: const Text(
                'Réinitialiser mes données',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
              subtitle: const Text(
                'Efface journal, pesées, recettes et aliments perso',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              trailing: const Icon(
                LucideIcons.chevronRight,
                size: 17,
                color: AppColors.textMuted,
              ),
              onTap: () => _confirmResetData(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

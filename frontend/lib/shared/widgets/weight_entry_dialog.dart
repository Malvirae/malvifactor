import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';

Future<void> showManualWeightDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final weightCtrl = TextEditingController();
  final fatCtrl = TextEditingController();

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Ajouter une pesée'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: weightCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTheme.numericStyle(fontSize: 16),
            decoration: const InputDecoration(
              labelText: 'Poids (kg)',
              hintText: '72.4',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: fatCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTheme.numericStyle(fontSize: 16),
            decoration: const InputDecoration(
              labelText: 'Masse grasse % (optionnel)',
              hintText: '15.2',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () async {
            final weight = double.tryParse(
              weightCtrl.text.trim().replaceAll(',', '.'),
            );
            if (weight == null || weight <= 20 || weight >= 350) return;
            final fatRaw = fatCtrl.text.trim().replaceAll(',', '.');
            final fat = fatRaw.isEmpty ? null : double.tryParse(fatRaw);

            await ref.read(dashboardRepositoryProvider).createManualWeight(
                  measuredAt: DateTime.now(),
                  weightKg: weight,
                  bodyFatPct: fat,
                );
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );

  if (saved == true) {
    ref.invalidate(dashboardProvider);
    ref.invalidate(fullMetricContextProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pesée enregistrée et tendance EWMA recalculée.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}

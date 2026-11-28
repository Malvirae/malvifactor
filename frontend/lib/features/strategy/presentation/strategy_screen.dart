import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/profile/data/profile_repository.dart';
import 'package:malvifactor/features/profile/presentation/profile_screen.dart';
import 'package:malvifactor/features/profile/providers/profile_provider.dart';
import 'package:malvifactor/features/strategy/data/strategy_repository.dart';

class StrategyData {
  const StrategyData({
    required this.profile,
    required this.preview,
    required this.history,
  });

  final UserProfileModel profile;
  final CheckinPreviewModel preview;
  final List<WeeklyCheckinModel> history;
}

final strategyProvider = FutureProvider<StrategyData>((ref) async {
  final profileRepo = ref.watch(profileRepositoryProvider);
  final strategyRepo = ref.watch(strategyRepositoryProvider);

  final results = await Future.wait<dynamic>([
    profileRepo.fetchProfile(),
    strategyRepo.fetchPreview(),
    strategyRepo.listCheckins(),
  ]);

  return StrategyData(
    profile: results[0] as UserProfileModel,
    preview: results[1] as CheckinPreviewModel,
    history: results[2] as List<WeeklyCheckinModel>,
  );
});

/// True strictly on the user's configured check-in day (never on J-1) when not done yet.
final strategyCheckinBadgeProvider = Provider<bool>((ref) {
  final strategyAsync = ref.watch(strategyProvider);
  return strategyAsync.maybeWhen(
    data: (data) {
      final todayWeekday = DateTime.now().weekday - 1; // 0=Mon..6=Sun
      if (todayWeekday != data.profile.checkinDay) return false;
      return data.preview.isDue;
    },
    orElse: () => false,
  );
});

class StrategyScreen extends ConsumerWidget {
  const StrategyScreen({super.key});

  int _daysUntilCheckin(UserProfileModel profile, CheckinPreviewModel preview) {
    if (preview.isDue) return 0;
    final todayWeekday = DateTime.now().weekday - 1; // 0=Mon..6=Sun
    var diff = (profile.checkinDay - todayWeekday) % 7;
    if (diff == 0) diff = 7;
    return diff;
  }

  String _weekdayName(int weekdayIndex) {
    const names = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche',
    ];
    return names[weekdayIndex % 7];
  }

  String _goalLabel(String goalType) {
    switch (goalType) {
      case 'lose':
        return 'Perte de poids';
      case 'gain':
        return 'Prise de masse';
      default:
        return 'Maintien';
    }
  }

  Future<void> _openCheckinReview(
    BuildContext context,
    WidgetRef ref,
    StrategyData data,
  ) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _CheckinReviewSheet(
        profile: data.profile,
        preview: data.preview,
      ),
    );
    if (accepted == true) {
      ref.invalidate(strategyProvider);
      ref.invalidate(profileProvider);
      ref.invalidate(dashboardProvider);
      ref.invalidate(fullMetricContextProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strategyAsync = ref.watch(strategyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'STRATÉGIE',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.calories,
        backgroundColor: AppColors.surface,
        onRefresh: () => ref.refresh(strategyProvider.future),
        child: strategyAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.calories),
          ),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [Text('Erreur : $e')],
          ),
          data: (data) {
            final daysLeft = _daysUntilCheckin(data.profile, data.preview);
            final ringProgress = ((7 - daysLeft) / 7.0).clamp(0.1, 1.0);
            const dayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Center(
                  child: SizedBox(
                    width: 174,
                    height: 174,
                    child: CustomPaint(
                      painter: _CountdownRingPainter(
                        progress: ringProgress,
                        color: data.preview.isDue
                            ? AppColors.calories
                            : AppColors.textPrimary,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              data.preview.isDue
                                  ? 'CHECK-IN'
                                  : '$daysLeft ${daysLeft > 1 ? 'JOURS' : 'JOUR'}',
                              style: AppTheme.numericStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: data.preview.isDue
                                    ? AppColors.calories
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              data.preview.isDue
                                  ? 'disponible'
                                  : 'avant le check-in',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Column(
                    children: [
                      OutlinedButton.icon(
                        onPressed: data.preview.isDue
                            ? () => _openCheckinReview(context, ref, data)
                            : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: data.preview.isDue
                              ? AppColors.calories
                              : AppColors.textMuted,
                          disabledForegroundColor: AppColors.textMuted,
                          side: BorderSide(
                            color: data.preview.isDue
                                ? AppColors.calories
                                : AppColors.border,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(LucideIcons.calendarCheck, size: 18),
                        label: const Text(
                          'Check-In',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (!data.preview.isDue) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Disponible ${_weekdayName((data.profile.checkinDay - 1) % 7)} ou ${_weekdayName(data.profile.checkinDay)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'En cours',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: AppTheme.matteCardDecoration(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Programme Coaché',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'TDEE estimé : ${data.profile.currentTdeeKcal.round()} kcal · ${_goalLabel(data.profile.goalType)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: List.generate(7, (idx) {
                          return Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2.5),
                              child: Column(
                                children: [
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppColors.calories,
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Text(
                                      '${data.profile.currentCalorieTarget.round()}',
                                      style: AppTheme.numericStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  _MacroBlock(
                                    text:
                                        '${data.profile.currentProteinG.round()} P',
                                    color: AppColors.protein,
                                  ),
                                  const SizedBox(height: 4),
                                  _MacroBlock(
                                    text:
                                        '${data.profile.currentFatG.round()} L',
                                    color: AppColors.fat,
                                  ),
                                  const SizedBox(height: 4),
                                  _MacroBlock(
                                    text:
                                        '${data.profile.currentCarbsG.round()} G',
                                    color: AppColors.carbs,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    dayLetters[idx],
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(
                                mode: ProfileEditMode.program,
                              ),
                            ),
                          );
                          ref.invalidate(strategyProvider);
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(LucideIcons.pencil, size: 15),
                        label: const Text('Modifier le programme'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: AppTheme.matteCardDecoration(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Objectif actuel',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_goalLabel(data.profile.goalType)} · ${data.profile.targetRateKgPerWeek >= 0 ? '+' : ''}${data.profile.targetRateKgPerWeek.toStringAsFixed(2)} kg / semaine',
                        style: AppTheme.numericStyle(
                          fontSize: 14,
                          color: AppColors.calories,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Historique des check-ins',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                if (data.history.isEmpty)
                  Container(
                    decoration: AppTheme.matteCardDecoration(),
                    padding: const EdgeInsets.all(18),
                    child: const Text(
                      'Aucun check-in validé pour le moment.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  ...data.history.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        decoration: AppTheme.matteCardDecoration(),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat('dd MMM yyyy', 'fr_FR')
                                      .format(c.checkinDate),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'TDEE ${c.calculatedTdeeKcal.round()} kcal · ${c.daysLoggedCount} j loggés',
                                  style: AppTheme.numericStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${c.newCalorieTarget.round()} kcal',
                              style: AppTheme.numericStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.calories,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MacroBlock extends StatelessWidget {
  const _MacroBlock({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          style: AppTheme.numericStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.background,
          ),
        ),
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  _CountdownRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = AppColors.surfaceElevated
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    final activePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _CheckinReviewSheet extends ConsumerStatefulWidget {
  const _CheckinReviewSheet({
    required this.profile,
    required this.preview,
  });

  final UserProfileModel profile;
  final CheckinPreviewModel preview;

  @override
  ConsumerState<_CheckinReviewSheet> createState() =>
      _CheckinReviewSheetState();
}

class _CheckinReviewSheetState extends ConsumerState<_CheckinReviewSheet> {
  bool _submitting = false;

  Future<void> _accept() async {
    setState(() => _submitting = true);
    try {
      await ref.read(strategyRepositoryProvider).acceptCheckin();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final prof = widget.profile;
    final weightDelta = p.endTrendWeightKg - p.startTrendWeightKg;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Bilan hebdomadaire',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${DateFormat('dd/MM').format(p.periodStart)} → ${DateFormat('dd/MM').format(p.periodEnd)} · Confiance : ${p.confidence.toUpperCase()}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: AppTheme.matteCardDecoration(),
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _CompareRow(
                  label: 'Apport moyen (${p.daysLoggedCount} j)',
                  value: '${p.avgIntakeKcal.round()} kcal/j',
                ),
                const SizedBox(height: 8),
                _CompareRow(
                  label: 'Variation tendance de poids',
                  value:
                      '${weightDelta >= 0 ? '+' : ''}${weightDelta.toStringAsFixed(2)} kg',
                ),
                const SizedBox(height: 8),
                _CompareRow(
                  label: 'TDEE estimé',
                  value:
                      '${p.previousTdeeKcal.round()} → ${p.calculatedTdeeKcal.round()} kcal',
                ),
                const Divider(height: 20),
                _CompareRow(
                  label: 'Cible calorique',
                  value:
                      '${prof.currentCalorieTarget.round()} → ${p.newCalorieTarget.round()} kcal',
                  highlightColor: AppColors.calories,
                ),
                const SizedBox(height: 6),
                _CompareRow(
                  label: 'Protéines',
                  value:
                      '${prof.currentProteinG.round()}g → ${p.newProteinG.round()}g',
                  highlightColor: AppColors.protein,
                ),
                const SizedBox(height: 6),
                _CompareRow(
                  label: 'Lipides',
                  value: '${prof.currentFatG.round()}g → ${p.newFatG.round()}g',
                  highlightColor: AppColors.fat,
                ),
                const SizedBox(height: 6),
                _CompareRow(
                  label: 'Glucides',
                  value:
                      '${prof.currentCarbsG.round()}g → ${p.newCarbsG.round()}g',
                  highlightColor: AppColors.carbs,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: (_submitting || !p.isDue) ? null : _accept,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.background,
                    ),
                  )
                : const Text('Accepter et appliquer ces macros'),
          ),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.value,
    this.highlightColor,
  });

  final String label;
  final String value;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: AppTheme.numericStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: highlightColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

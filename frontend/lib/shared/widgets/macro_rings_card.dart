import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/core/widgets/pressable_scale.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';

class MacroRingsCard extends StatefulWidget {
  const MacroRingsCard({
    super.key,
    required this.totals,
    required this.targets,
    required this.remaining,
    this.title = 'Nutrition du jour',
  });

  final MacroSummaryModel totals;
  final MacroSummaryModel targets;
  final MacroSummaryModel remaining;
  final String title;

  @override
  State<MacroRingsCard> createState() => _MacroRingsCardState();
}

class _MacroRingsCardState extends State<MacroRingsCard> {
  bool _showRemaining = false;

  @override
  Widget build(BuildContext context) {
    final safeKcalTarget = widget.targets.kcal <= 0 ? 1.0 : widget.targets.kcal;
    final kcalProgress = (widget.totals.kcal / safeKcalTarget).clamp(0.0, 1.0);
    final isOverKcal =
        widget.totals.kcal > widget.targets.kcal && widget.targets.kcal > 0;
    final clampedRemainingKcal =
        (widget.targets.kcal - widget.totals.kcal).clamp(0.0, double.infinity);

    final centerValue = _showRemaining
        ? clampedRemainingKcal.round()
        : widget.totals.kcal.round();
    final centerLabel = _showRemaining ? 'Restantes' : 'Consommées';

    return Container(
      decoration: AppTheme.gradientCardDecoration(
        accentColor: AppColors.calories,
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SideMetric(
                  value: clampedRemainingKcal.round().toString(),
                  label: 'Restant',
                  color: isOverKcal ? AppColors.error : AppColors.textPrimary,
                ),
              ),
              RepaintBoundary(
                child: SizedBox(
                  width: 164,
                  height: 148,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: kcalProgress),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    builder: (_, animatedProgress, child) => CustomPaint(
                      painter: _CalorieArcPainter(
                        progress: animatedProgress,
                        trackColor: AppColors.surfaceElevated,
                        progressColor:
                            isOverKcal ? AppColors.error : AppColors.calories,
                      ),
                      child: child,
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          child: Column(
                            key: ValueKey<String>('${_showRemaining}_$centerValue'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$centerValue',
                                style: AppTheme.numericStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: isOverKcal && _showRemaining
                                      ? AppColors.error
                                      : AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                centerLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _SideMetric(
                  value: widget.targets.kcal.round().toString(),
                  label: 'Cible',
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _CompactMacroColumn(
                  label: 'Protéines',
                  consumed: widget.totals.proteinG,
                  target: widget.targets.proteinG,
                  remaining: widget.remaining.proteinG,
                  showRemaining: _showRemaining,
                  color: AppColors.protein,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CompactMacroColumn(
                  label: 'Lipides',
                  consumed: widget.totals.fatG,
                  target: widget.targets.fatG,
                  remaining: widget.remaining.fatG,
                  showRemaining: _showRemaining,
                  color: AppColors.fat,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CompactMacroColumn(
                  label: 'Glucides',
                  consumed: widget.totals.carbsG,
                  target: widget.targets.carbsG,
                  remaining: widget.remaining.carbsG,
                  showRemaining: _showRemaining,
                  color: AppColors.carbs,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ModePill(
                    label: 'Consommé',
                    selected: !_showRemaining,
                    onTap: () => setState(() => _showRemaining = false),
                  ),
                  _ModePill(
                    label: 'Restant',
                    selected: _showRemaining,
                    onTap: () => setState(() => _showRemaining = true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideMetric extends StatelessWidget {
  const _SideMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTheme.numericStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _CompactMacroColumn extends StatelessWidget {
  const _CompactMacroColumn({
    required this.label,
    required this.consumed,
    required this.target,
    required this.remaining,
    required this.showRemaining,
    required this.color,
  });

  final String label;
  final double consumed;
  final double target;
  final double remaining;
  final bool showRemaining;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safeTarget = target <= 0 ? 1.0 : target;
    final ratio = (consumed / safeTarget).clamp(0.0, 1.0);
    final isOver = consumed > target && target > 0;
    final clampedRemaining = (target - consumed).clamp(0.0, double.infinity);
    final displayText = showRemaining
        ? '${clampedRemaining.round()}g rest.'
        : '${consumed.round()} / ${target.round()}g';

    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedMacroBar(
          value: ratio,
          minHeight: 5,
          backgroundColor: AppColors.surfaceElevated,
          color: isOver ? AppColors.error : color,
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          child: Text(
            displayText,
            key: ValueKey<String>(displayText),
            style: AppTheme.numericStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isOver && showRemaining
                  ? AppColors.error
                  : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.background : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _CalorieArcPainter extends CustomPainter {
  _CalorieArcPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 10.0;
    const startAngle = 135.0 * math.pi / 180.0;
    const sweepTotal = 270.0 * math.pi / 180.0;

    final center = Offset(size.width / 2, size.height / 2 + 4);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepTotal, false, trackPaint);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        startAngle,
        sweepTotal * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CalorieArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor;
  }
}

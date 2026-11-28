import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';

/// MacroFactor-style Weekly Nutrition module (page 2 of the Dashboard carousel).
class WeeklyNutritionCard extends StatefulWidget {
  const WeeklyNutritionCard({
    super.key,
    required this.weekly,
    this.fillHeight = true,
  });

  final WeeklyNutritionModel weekly;
  final bool fillHeight;

  @override
  State<WeeklyNutritionCard> createState() => _WeeklyNutritionCardState();
}

class _WeeklyNutritionCardState extends State<WeeklyNutritionCard> {
  static const List<String> _dayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const List<String> _shortDayNames = [
    'LUN.',
    'MAR.',
    'MER.',
    'JEU.',
    'VEN.',
    'SAM.',
    'DIM.',
  ];

  bool _showRemaining = false;
  int? _selectedDayIndex;
  bool _hasInitializedSelection = false;

  @override
  void initState() {
    super.initState();
    _initDefaultSelection();
  }

  @override
  void didUpdateWidget(covariant WeeklyNutritionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasInitializedSelection) {
      _initDefaultSelection();
    } else if (_selectedDayIndex != null &&
        _selectedDayIndex! >= widget.weekly.days.length) {
      _initDefaultSelection();
    }
  }

  void _initDefaultSelection() {
    final days = widget.weekly.days;
    if (days.isEmpty) {
      _selectedDayIndex = null;
      return;
    }
    final todayIdx = days.indexWhere((d) => d.isToday);
    _selectedDayIndex = todayIdx >= 0
        ? todayIdx
        : (DateTime.now().weekday - 1).clamp(0, days.length - 1);
    _hasInitializedSelection = true;
  }

  String _formatFrInt(int value) {
    final neg = value < 0;
    final digits = value.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final posFromRight = digits.length - i;
      if (i > 0 && posFromRight % 3 == 0) {
        buf.write('\u00A0');
      }
      buf.write(digits[i]);
    }
    return neg ? '-$buf' : buf.toString();
  }

  void _onTapDay(int idx) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedDayIndex == idx) {
        _selectedDayIndex = null;
      } else {
        _selectedDayIndex = idx;
      }
    });
  }

  void _onTapSummaryColumn() {
    if (_selectedDayIndex == null) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedDayIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.weekly.days;
    final selectedDay =
        (_selectedDayIndex != null && _selectedDayIndex! < days.length)
            ? days[_selectedDayIndex!]
            : null;

    final double consumedKcal;
    final double consumedP;
    final double consumedF;
    final double consumedC;
    final double targetKcal;
    final double targetP;
    final double targetF;
    final double targetC;

    if (selectedDay != null) {
      consumedKcal = selectedDay.consumedKcal;
      consumedP = selectedDay.consumedProteinG;
      consumedF = selectedDay.consumedFatG;
      consumedC = selectedDay.consumedCarbsG;
      targetKcal = selectedDay.targetKcal;
      targetP = selectedDay.targetProteinG;
      targetF = selectedDay.targetFatG;
      targetC = selectedDay.targetCarbsG;
    } else {
      final wt = widget.weekly.weekTotals;
      consumedKcal = wt.consumedKcal;
      consumedP = wt.consumedProteinG;
      consumedF = wt.consumedFatG;
      consumedC = wt.consumedCarbsG;
      targetKcal = wt.targetKcal;
      targetP = wt.targetProteinG;
      targetF = wt.targetFatG;
      targetC = wt.targetCarbsG;
    }

    String? rightBottomLabel;
    bool rightBottomActive = false;
    if (selectedDay == null) {
      rightBottomLabel = 'SEM.';
      rightBottomActive = true;
    } else if (!selectedDay.isToday) {
      final dayIdx = (selectedDay.dayOfWeek - 1).clamp(0, 6);
      rightBottomLabel = _shortDayNames[dayIdx];
      rightBottomActive = false;
    }

    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final animKey = '${_selectedDayIndex ?? 'week'}_$_showRemaining';

    return RepaintBoundary(
      child: Container(
        decoration: AppTheme.gradientCardDecoration(
          accentColor: AppColors.calories,
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nutrition hebdomadaire',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left ~72%: 7 calendar days x 4 vertical macro gauges
                  Expanded(
                    flex: 72,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < days.length; i++)
                          Expanded(
                            child: _DayGaugeColumn(
                              day: days[i],
                              letter: _dayLetters[i % 7],
                              isSelected: _selectedDayIndex == i,
                              showRemaining: _showRemaining,
                              disableAnimations: disableAnimations,
                              onTap: () => _onTapDay(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Right ~28%: 4 aligned numeric summary rows + SEM. / day label
                  Expanded(
                    flex: 28,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _onTapSummaryColumn,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _RightMacroSummaryBlock(
                              animKey: '${animKey}_kcal',
                              consumed: consumedKcal,
                              target: targetKcal,
                              showRemaining: _showRemaining,
                              isCalories: true,
                              unitLetter: null,
                              unitColor: AppColors.calories,
                              formatInt: _formatFrInt,
                              disableAnimations: disableAnimations,
                            ),
                            _RightMacroSummaryBlock(
                              animKey: '${animKey}_p',
                              consumed: consumedP,
                              target: targetP,
                              showRemaining: _showRemaining,
                              isCalories: false,
                              unitLetter: 'P',
                              unitColor: AppColors.protein,
                              formatInt: _formatFrInt,
                              disableAnimations: disableAnimations,
                            ),
                            _RightMacroSummaryBlock(
                              animKey: '${animKey}_f',
                              consumed: consumedF,
                              target: targetF,
                              showRemaining: _showRemaining,
                              isCalories: false,
                              unitLetter: 'L',
                              unitColor: AppColors.fat,
                              formatInt: _formatFrInt,
                              disableAnimations: disableAnimations,
                            ),
                            _RightMacroSummaryBlock(
                              animKey: '${animKey}_c',
                              consumed: consumedC,
                              target: targetC,
                              showRemaining: _showRemaining,
                              isCalories: false,
                              unitLetter: 'G',
                              unitColor: AppColors.carbs,
                              formatInt: _formatFrInt,
                              disableAnimations: disableAnimations,
                            ),
                            SizedBox(
                              height: 18,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: AnimatedSwitcher(
                                  duration: disableAnimations
                                      ? Duration.zero
                                      : const Duration(milliseconds: 160),
                                  child: rightBottomLabel != null
                                      ? Text(
                                          rightBottomLabel,
                                          key: ValueKey<String>(
                                            rightBottomLabel,
                                          ),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: rightBottomActive
                                                ? FontWeight.w800
                                                : FontWeight.w700,
                                            letterSpacing: 0.4,
                                            color: rightBottomActive
                                                ? AppColors.textPrimary
                                                : const Color(0xFF94A3B8),
                                          ),
                                        )
                                      : const SizedBox.shrink(
                                          key: ValueKey<String>('empty'),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
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
                    _WeeklyModePill(
                      label: 'Consommé',
                      selected: !_showRemaining,
                      onTap: () => setState(() => _showRemaining = false),
                    ),
                    _WeeklyModePill(
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
      ),
    );
  }
}

class _DayGaugeColumn extends StatelessWidget {
  const _DayGaugeColumn({
    required this.day,
    required this.letter,
    required this.isSelected,
    required this.showRemaining,
    required this.disableAnimations,
    required this.onTap,
  });

  final WeeklyNutritionDayModel day;
  final String letter;
  final bool isSelected;
  final bool showRemaining;
  final bool disableAnimations;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.white70 : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _VerticalMacroGauge(
              consumed: day.consumedKcal,
              target: day.targetKcal,
              color: AppColors.calories,
              isFuture: day.isFuture,
              showRemaining: showRemaining,
              disableAnimations: disableAnimations,
            ),
            _VerticalMacroGauge(
              consumed: day.consumedProteinG,
              target: day.targetProteinG,
              color: AppColors.protein,
              isFuture: day.isFuture,
              showRemaining: showRemaining,
              disableAnimations: disableAnimations,
            ),
            _VerticalMacroGauge(
              consumed: day.consumedFatG,
              target: day.targetFatG,
              color: AppColors.fat,
              isFuture: day.isFuture,
              showRemaining: showRemaining,
              disableAnimations: disableAnimations,
            ),
            _VerticalMacroGauge(
              consumed: day.consumedCarbsG,
              target: day.targetCarbsG,
              color: AppColors.carbs,
              isFuture: day.isFuture,
              showRemaining: showRemaining,
              disableAnimations: disableAnimations,
            ),
            SizedBox(
              height: 18,
              child: Center(
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: day.isToday ? FontWeight.w800 : FontWeight.w600,
                    color: day.isToday
                        ? AppColors.textPrimary
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerticalMacroGauge extends StatelessWidget {
  const _VerticalMacroGauge({
    required this.consumed,
    required this.target,
    required this.color,
    required this.isFuture,
    required this.showRemaining,
    required this.disableAnimations,
  });

  static const double _trackWidth = 19.0;
  static const double _trackHeight = 38.0;
  static const double _targetLineFraction = 0.85;

  final double consumed;
  final double target;
  final Color color;
  final bool isFuture;
  final bool showRemaining;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final safeConsumed = math.max(0.0, consumed);
    final safeTarget = math.max(0.0, target);
    final isMutedFuture = isFuture && safeConsumed <= 0.01;

    double barBottomFrac;
    double barTopFrac;
    Color barColor;

    if (!showRemaining) {
      // Consommé mode: grows bottom -> up, can overshoot above the 85% target line.
      barBottomFrac = 0.0;
      if (isMutedFuture || safeTarget <= 0 || safeConsumed <= 0) {
        barTopFrac = 0.0;
      } else {
        final ratio = safeConsumed / safeTarget;
        if (ratio <= 1.0) {
          barTopFrac = ratio * _targetLineFraction;
        } else {
          final overshoot = math.min(0.15, (ratio - 1.0) * 0.30);
          barTopFrac = (_targetLineFraction + overshoot).clamp(0.85, 1.0);
        }
      }
      barColor = color;
    } else {
      // Restant mode: anchored at the 85% target line and hangs downward.
      barTopFrac = _targetLineFraction;
      if (isMutedFuture) {
        barBottomFrac = 0.0;
        barColor = Colors.white.withValues(alpha: 0.14);
      } else if (safeTarget <= 0) {
        barBottomFrac = _targetLineFraction;
        barColor = color;
      } else {
        final remRatio = ((safeTarget - safeConsumed) / safeTarget).clamp(
          0.0,
          1.0,
        );
        barBottomFrac = _targetLineFraction * (1.0 - remRatio);
        barColor = color;
      }
    }

    final barBottomPx = _trackHeight * barBottomFrac;
    final barHeightPx = math.max(0.0, _trackHeight * (barTopFrac - barBottomFrac));
    final animDuration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return Container(
      width: _trackWidth,
      height: _trackHeight,
      decoration: BoxDecoration(
        color: isMutedFuture
            ? const Color(0xFF191B20)
            : const Color(0xFF1E2026),
        borderRadius: BorderRadius.circular(4.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Target 100% reference line at 85% height (15% from top)
          Positioned(
            top: _trackHeight * (1.0 - _targetLineFraction),
            left: 0,
            right: 0,
            child: Container(
              height: 1.2,
              color: Colors.white.withValues(alpha: isMutedFuture ? 0.14 : 0.28),
            ),
          ),
          // Animated centered inner gauge bar
          AnimatedPositioned(
            duration: animDuration,
            curve: Curves.easeOutCubic,
            left: 5,
            right: 5,
            bottom: barBottomPx,
            height: barHeightPx,
            child: AnimatedContainer(
              duration: animDuration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RightMacroSummaryBlock extends StatelessWidget {
  const _RightMacroSummaryBlock({
    required this.animKey,
    required this.consumed,
    required this.target,
    required this.showRemaining,
    required this.isCalories,
    required this.unitLetter,
    required this.unitColor,
    required this.formatInt,
    required this.disableAnimations,
  });

  final String animKey;
  final double consumed;
  final double target;
  final bool showRemaining;
  final bool isCalories;
  final String? unitLetter;
  final Color unitColor;
  final String Function(int) formatInt;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final targetInt = target.round();
    final int displayInt;
    final bool isOverRemaining;
    if (showRemaining) {
      final diff = targetInt - consumed.round();
      displayInt = diff;
      isOverRemaining = diff < 0 && targetInt > 0;
    } else {
      displayInt = consumed.round();
      isOverRemaining = false;
    }

    final valueText = formatInt(displayInt);
    final targetText = 'sur ${formatInt(targetInt)}';

    return SizedBox(
      height: 38,
      child: AnimatedSwitcher(
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 160),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.centerRight,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        child: Column(
          key: ValueKey<String>('${animKey}_${valueText}_$targetText'),
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    valueText,
                    style: AppTheme.numericStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: isOverRemaining
                          ? AppColors.error
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (isCalories) ...[
                    const SizedBox(width: 2.5),
                    Icon(
                      Icons.local_fire_department,
                      size: 14,
                      color: isOverRemaining ? AppColors.error : unitColor,
                    ),
                  ] else if (unitLetter != null) ...[
                    const SizedBox(width: 3),
                    Text(
                      unitLetter!,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: unitColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                targetText,
                style: AppTheme.numericStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyModePill extends StatelessWidget {
  const _WeeklyModePill({
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

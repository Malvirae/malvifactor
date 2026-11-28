import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';

class WeekDateStrip extends StatefulWidget {
  const WeekDateStrip({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.showHeaderRow = false,
    this.loggedDayKeys = const <String>{},
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final bool showHeaderRow;
  final Set<String> loggedDayKeys;

  @override
  State<WeekDateStrip> createState() => _WeekDateStripState();
}

class _WeekDateStripState extends State<WeekDateStrip> {
  int _slideDirection = 1; // 1 = forward (right -> left), -1 = backward
  double _weekDragDx = 0.0;

  DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _mondayOf(DateTime d) {
    final norm = _normalize(d);
    return norm.subtract(Duration(days: norm.weekday - 1));
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void didUpdateWidget(covariant WeekDateStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldMonday = _mondayOf(oldWidget.selectedDate);
    final newMonday = _mondayOf(widget.selectedDate);
    if (newMonday.isAfter(oldMonday)) {
      _slideDirection = 1;
    } else if (newMonday.isBefore(oldMonday)) {
      _slideDirection = -1;
    }
  }

  void _shiftWeek(int deltaDays) {
    HapticFeedback.selectionClick();
    _slideDirection = deltaDays > 0 ? 1 : -1;
    widget.onDateSelected(
      _normalize(widget.selectedDate).add(Duration(days: deltaDays)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalizedSelected = _normalize(widget.selectedDate);
    final today = _normalize(DateTime.now());
    final monday = _mondayOf(normalizedSelected);
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    final isTodaySelected = _isSameDay(normalizedSelected, today);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showHeaderRow) ...[
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Semaine précédente',
                onPressed: () => _shiftWeek(-7),
                icon: const Icon(
                  LucideIcons.chevronLeft,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy', 'fr_FR')
                      .format(normalizedSelected)
                      .toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (!isTodaySelected)
                TextButton(
                  onPressed: () => widget.onDateSelected(today),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.calories,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text(
                    'Aujourd’hui',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Semaine suivante',
                onPressed: () => _shiftWeek(7),
                icon: const Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => _weekDragDx = 0.0,
          onHorizontalDragUpdate: (details) => _weekDragDx += details.delta.dx,
          onHorizontalDragCancel: () => _weekDragDx = 0.0,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0.0;
            if (velocity > 240 || _weekDragDx > 48) {
              _shiftWeek(-7);
            } else if (velocity < -240 || _weekDragDx < -48) {
              _shiftWeek(7);
            }
            _weekDragDx = 0.0;
          },
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) {
              final isIncoming = child.key == ValueKey(monday);
              final beginOffset = isIncoming
                  ? Offset(0.22 * _slideDirection, 0)
                  : Offset(-0.22 * _slideDirection, 0);

              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: beginOffset,
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Row(
              key: ValueKey(monday),
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: days.map((day) {
                final isSelected = _isSameDay(day, normalizedSelected);
                final isToday = _isSameDay(day, today);
                final hasLogs = widget.loggedDayKeys.contains(_dayKey(day));
                final weekdayShort = DateFormat('EE', 'fr_FR')
                    .format(day)
                    .replaceAll('.', '')
                    .substring(0, 2);
                final capitalizedDay =
                    weekdayShort[0].toUpperCase() + weekdayShort.substring(1);

                final Color fillColor;
                final Color borderColor;
                final double borderWidth;
                if (isSelected) {
                  fillColor = const Color(0xFF232630);
                  borderColor = hasLogs
                      ? AppColors.calories.withValues(alpha: 0.72)
                      : Colors.white.withValues(alpha: 0.24);
                  borderWidth = 1.4;
                } else if (hasLogs) {
                  fillColor = const Color(0xFF171920);
                  borderColor = AppColors.calories.withValues(alpha: 0.45);
                  borderWidth = 1.1;
                } else {
                  fillColor = const Color(0xFF15171D);
                  borderColor = Colors.white.withValues(alpha: 0.06);
                  borderWidth = 0.9;
                }

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onDateSelected(day);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: borderColor,
                          width: borderWidth,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${day.day}',
                            style: AppTheme.numericStyle(
                              fontSize: 13.5,
                              fontWeight: isSelected || isToday
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : isToday
                                      ? AppColors.calories
                                      : hasLogs
                                          ? const Color(0xFFE2E8F0)
                                          : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 1.5),
                          Text(
                            capitalizedDay,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? const Color(0xFFE2E8F0)
                                  : AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: isSelected ? 4.5 : 3.5,
                            height: isSelected ? 4.5 : 3.5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? const Color(0xFFF8FAFC)
                                  : isToday
                                      ? AppColors.calories.withValues(
                                          alpha: 0.65,
                                        )
                                      : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

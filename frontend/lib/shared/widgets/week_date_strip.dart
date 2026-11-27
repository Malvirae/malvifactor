import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';

class WeekDateStrip extends StatefulWidget {
  const WeekDateStrip({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.showHeaderRow = true,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final bool showHeaderRow;

  @override
  State<WeekDateStrip> createState() => _WeekDateStripState();
}

class _WeekDateStripState extends State<WeekDateStrip> {
  int _slideDirection = 1; // 1 = forward (right -> left), -1 = backward

  DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _mondayOf(DateTime d) {
    final norm = _normalize(d);
    return norm.subtract(Duration(days: norm.weekday - 1));
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
                onPressed: () {
                  _slideDirection = -1;
                  widget.onDateSelected(
                    normalizedSelected.subtract(const Duration(days: 7)),
                  );
                },
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
                onPressed: () {
                  _slideDirection = 1;
                  widget.onDateSelected(
                    normalizedSelected.add(const Duration(days: 7)),
                  );
                },
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
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) {
            final isIncoming = child.key == ValueKey(monday);
            final beginOffset = isIncoming
                ? Offset(0.25 * _slideDirection, 0)
                : Offset(-0.25 * _slideDirection, 0);

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
              final weekdayShort = DateFormat('EE', 'fr_FR')
                  .format(day)
                  .replaceAll('.', '')
                  .substring(0, 2);
              final capitalizedDay =
                  weekdayShort[0].toUpperCase() + weekdayShort.substring(1);

              return Expanded(
                child: GestureDetector(
                  onTap: () => widget.onDateSelected(day),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.surfaceElevated
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.calories
                            : isToday
                                ? AppColors.calories.withValues(alpha: 0.45)
                                : AppColors.border,
                        width: isSelected ? 1.8 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${day.day}',
                          style: AppTheme.numericStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          capitalizedDay,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? AppColors.calories
                                : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isToday
                                ? AppColors.calories
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
      ],
    );
  }
}

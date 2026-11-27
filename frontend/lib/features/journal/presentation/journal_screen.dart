import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/config/journal_preferences_provider.dart';
import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/food_logger/presentation/food_logger_sheet.dart';
import 'package:malvifactor/features/journal/data/journal_repository.dart';
import 'package:malvifactor/shared/widgets/week_date_strip.dart';

enum BatchActionType { copy, move }

final journalDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

class JournalDayNotifier extends AsyncNotifier<DayLogsModel> {
  @override
  Future<DayLogsModel> build() async {
    final date = ref.watch(journalDateProvider);
    return ref.watch(dashboardRepositoryProvider).fetchDayLogs(date);
  }

  Future<String?> optimisticDelete(String logId) =>
      optimisticBatchDelete({logId});

  Future<String?> optimisticBatchDelete(Set<String> logIds) async {
    final current = state.valueOrNull;
    if (current == null || logIds.isEmpty) return null;

    final updatedEntries =
        current.entries.where((entry) => !logIds.contains(entry.id)).toList();

    final newTotals = MacroSummaryModel(
      kcal: updatedEntries.fold<double>(0, (s, e) => s + e.kcal),
      proteinG: updatedEntries.fold<double>(0, (s, e) => s + e.proteinG),
      fatG: updatedEntries.fold<double>(0, (s, e) => s + e.fatG),
      carbsG: updatedEntries.fold<double>(0, (s, e) => s + e.carbsG),
    );
    final newRemaining = MacroSummaryModel(
      kcal: current.targets.kcal - newTotals.kcal,
      proteinG: current.targets.proteinG - newTotals.proteinG,
      fatG: current.targets.fatG - newTotals.fatG,
      carbsG: current.targets.carbsG - newTotals.carbsG,
    );

    state = AsyncData(
      DayLogsModel(
        date: current.date,
        entries: updatedEntries,
        totals: newTotals,
        targets: current.targets,
        remaining: newRemaining,
      ),
    );

    try {
      final repo = ref.read(journalRepositoryProvider);
      if (logIds.length == 1) {
        await repo.deleteLog(logIds.first);
      } else {
        await repo.batchDeleteLogs(logIds.toList());
      }
      ref.invalidate(dashboardProvider);
      return null;
    } catch (e) {
      state = AsyncData(current);
      ref.invalidateSelf();
      return 'Impossible de supprimer : $e';
    }
  }
}

final journalDayProvider =
    AsyncNotifierProvider<JournalDayNotifier, DayLogsModel>(
  JournalDayNotifier.new,
);

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final Set<String> _selectedIds = {};
  BatchActionType? _pendingBatchAction;
  List<String> _pendingLogIds = [];
  int _daySlideDirection = 1;
  double _dragDistanceX = 0;

  void _changeDate(DateTime nextDate) {
    final current = ref.read(journalDateProvider);
    final normCur = DateTime(current.year, current.month, current.day);
    final normNext = DateTime(nextDate.year, nextDate.month, nextDate.day);
    setState(() {
      _selectedIds.clear();
      _daySlideDirection = normNext.isBefore(normCur) ? -1 : 1;
    });
    ref.read(journalDateProvider.notifier).state = normNext;
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll(List<FoodLogItemModel> entries) {
    setState(() {
      if (_selectedIds.length == entries.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(entries.map((e) => e.id));
      }
    });
  }

  void _startPendingBatchAction(BatchActionType action) {
    if (_selectedIds.isEmpty) return;
    setState(() {
      _pendingBatchAction = action;
      _pendingLogIds = _selectedIds.toList();
      _selectedIds.clear();
    });
  }

  void _cancelPendingBatchAction() {
    setState(() {
      _pendingBatchAction = null;
      _pendingLogIds = [];
    });
  }

  Future<void> _executePendingAtHour(DateTime targetDate, int hour) async {
    final action = _pendingBatchAction;
    final ids = List<String>.from(_pendingLogIds);
    if (action == null || ids.isEmpty) return;

    final targetTime = TimeOfDay(hour: hour, minute: 0);
    setState(() {
      _pendingBatchAction = null;
      _pendingLogIds = [];
    });

    try {
      final repo = ref.read(journalRepositoryProvider);
      if (action == BatchActionType.copy) {
        await repo.copyLogIds(
          logIds: ids,
          targetDate: targetDate,
          targetTime: targetTime,
        );
      } else {
        await repo.moveLogIds(
          logIds: ids,
          targetDate: targetDate,
          targetTime: targetTime,
        );
      }
      ref.invalidate(journalDayProvider);
      ref.invalidate(dashboardProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == BatchActionType.copy
                ? '${ids.length} aliment(s) copié(s) à ${hour.toString().padLeft(2, '0')}:00.'
                : '${ids.length} aliment(s) déplacé(s) à ${hour.toString().padLeft(2, '0')}:00.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openMultiDateCopy(DateTime currentDate) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;

    final selectedDates = await showDialog<Set<DateTime>>(
      context: context,
      builder: (_) => _MultiDatePickerDialog(initialMonth: currentDate),
    );
    if (selectedDates == null || selectedDates.isEmpty || !mounted) return;

    try {
      final repo = ref.read(journalRepositoryProvider);
      for (final d in selectedDates) {
        await repo.copyLogIds(
          logIds: ids,
          targetDate: d,
          targetTime: null,
        );
      }
      setState(() => _selectedIds.clear());
      ref.invalidate(journalDayProvider);
      ref.invalidate(dashboardProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Copié vers ${selectedDates.length} jour(s).',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la copie multi-dates : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _batchDelete() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Supprimer la sélection ?'),
        content: Text(
          '$count entrée${count > 1 ? 's' : ''} seront supprimées.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final idsToDelete = Set<String>.from(_selectedIds);
    setState(() => _selectedIds.clear());

    final error = await ref
        .read(journalDayProvider.notifier)
        .optimisticBatchDelete(idsToDelete);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _copyToTargetDate(
    BuildContext context,
    WidgetRef ref,
    DateTime sourceDate,
  ) async {
    final targetDate = await showDatePicker(
      context: context,
      initialDate: sourceDate.add(const Duration(days: 1)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('fr', 'FR'),
    );
    if (targetDate == null || !context.mounted) return;

    try {
      await ref.read(journalRepositoryProvider).copyDay(
            sourceDate: sourceDate,
            targetDate: targetDate,
          );
      ref.invalidate(journalDayProvider);
      ref.invalidate(dashboardProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Journée copiée vers le ${DateFormat('dd/MM/yyyy').format(targetDate)}.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible de copier : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _duplicateYesterdayHere(
    BuildContext context,
    WidgetRef ref,
    DateTime targetDate,
  ) async {
    final yesterday = targetDate.subtract(const Duration(days: 1));
    try {
      await ref.read(journalRepositoryProvider).copyDay(
            sourceDate: yesterday,
            targetDate: targetDate,
          );
      ref.invalidate(journalDayProvider);
      ref.invalidate(dashboardProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Journée de la veille dupliquée ici.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aucune entrée à dupliquer ou erreur : $e'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  Future<void> _openEditLogSheet(
    BuildContext context,
    WidgetRef ref,
    FoodLogItemModel item,
  ) async {
    final isFreeEntry = item.foodId == null && item.recipeId == null;
    final canCustomizeFood = item.foodId != null;

    final qtyController = TextEditingController(
      text: item.quantityG.toStringAsFixed(item.quantityG % 1 == 0 ? 0 : 1),
    );
    final nameCtrl = TextEditingController(text: item.displayName);

    final scale100 =
        (!isFreeEntry && item.quantityG > 0) ? 100.0 / item.quantityG : 1.0;
    final initKcal = item.kcal * scale100;
    final initP = item.proteinG * scale100;
    final initF = item.fatG * scale100;
    final initC = item.carbsG * scale100;

    final kcalCtrl = TextEditingController(
      text: initKcal.toStringAsFixed(initKcal % 1 == 0 ? 0 : 1),
    );
    final pCtrl = TextEditingController(
      text: initP.toStringAsFixed(initP % 1 == 0 ? 0 : 1),
    );
    final fCtrl = TextEditingController(
      text: initF.toStringAsFixed(initF % 1 == 0 ? 0 : 1),
    );
    final cCtrl = TextEditingController(
      text: initC.toStringAsFixed(initC % 1 == 0 ? 0 : 1),
    );

    final parts = item.loggedTime.split(':');
    var selectedTime = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 12,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    var isSaving = false;

    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final currentQty = double.tryParse(
                  qtyController.text.replaceAll(',', '.'),
                ) ??
                item.quantityG;
            final curKcalBase =
                double.tryParse(kcalCtrl.text.replaceAll(',', '.')) ?? initKcal;
            final curPBase =
                double.tryParse(pCtrl.text.replaceAll(',', '.')) ?? initP;
            final curFBase =
                double.tryParse(fCtrl.text.replaceAll(',', '.')) ?? initF;
            final curCBase =
                double.tryParse(cCtrl.text.replaceAll(',', '.')) ?? initC;

            final previewFactor = isFreeEntry ? 1.0 : (currentQty / 100.0);

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.displayName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Portion : ${(curKcalBase * previewFactor).round()} kcal · P ${(curPBase * previewFactor).toStringAsFixed(1)}g · L ${(curFBase * previewFactor).toStringAsFixed(1)}g · G ${(curCBase * previewFactor).toStringAsFixed(1)}g',
                      style: AppTheme.numericStyle(
                        fontSize: 13,
                        color: AppColors.calories,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Quantité (g)',
                            ),
                            onChanged: (_) => setModalState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: ctx,
                                initialTime: selectedTime,
                              );
                              if (picked != null) {
                                setModalState(() => selectedTime = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Heure',
                                prefixIcon: Icon(LucideIcons.clock, size: 16),
                              ),
                              child: Text(
                                '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                                style: AppTheme.numericStyle(fontSize: 15),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (canCustomizeFood || isFreeEntry) ...[
                      const SizedBox(height: 16),
                      Text(
                        isFreeEntry
                            ? 'Valeurs de l’entrée'
                            : 'Valeurs nutritionnelles (pour 100 g)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nom'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: kcalCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Kcal',
                              ),
                              onChanged: (_) => setModalState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: pCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Prot (g)',
                              ),
                              onChanged: (_) => setModalState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: fCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Lip (g)',
                              ),
                              onChanged: (_) => setModalState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: cCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Glu (g)',
                              ),
                              onChanged: (_) => setModalState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final newQty = double.tryParse(
                                qtyController.text.replaceAll(',', '.'),
                              );
                              if (newQty == null || newQty <= 0) return;
                              setModalState(() => isSaving = true);

                              final journalRepo =
                                  ref.read(journalRepositoryProvider);
                              if (isFreeEntry) {
                                await journalRepo.updateLog(
                                  logId: item.id,
                                  customName: nameCtrl.text.trim(),
                                  quantityG: newQty,
                                  loggedTime: selectedTime,
                                  kcal: curKcalBase,
                                  proteinG: curPBase,
                                  fatG: curFBase,
                                  carbsG: curCBase,
                                );
                              } else if (canCustomizeFood) {
                                final macrosChanged =
                                    nameCtrl.text.trim() != item.displayName ||
                                        (curKcalBase - initKcal).abs() > 0.05 ||
                                        (curPBase - initP).abs() > 0.05 ||
                                        (curFBase - initF).abs() > 0.05 ||
                                        (curCBase - initC).abs() > 0.05;
                                if (macrosChanged) {
                                  final customized = await ref
                                      .read(foodRepositoryProvider)
                                      .customizeFood(
                                        foodId: item.foodId!,
                                        name: nameCtrl.text.trim(),
                                        kcalPer100g: curKcalBase,
                                        proteinPer100g: curPBase,
                                        fatPer100g: curFBase,
                                        carbsPer100g: curCBase,
                                      );
                                  await journalRepo.updateLog(
                                    logId: item.id,
                                    foodId: customized.id,
                                    quantityG: newQty,
                                    loggedTime: selectedTime,
                                  );
                                } else {
                                  await journalRepo.updateLog(
                                    logId: item.id,
                                    quantityG: newQty,
                                    loggedTime: selectedTime,
                                  );
                                }
                              } else {
                                await journalRepo.updateLog(
                                  logId: item.id,
                                  quantityG: newQty,
                                  loggedTime: selectedTime,
                                );
                              }

                              if (ctx.mounted) Navigator.of(ctx).pop(true);
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
          },
        );
      },
    );

    if (updated == true) {
      ref.invalidate(journalDayProvider);
      ref.invalidate(dashboardProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(journalDateProvider);
    final dayAsync = ref.watch(journalDayProvider);
    final isCompact = ref.watch(journalCompactModeProvider);
    final entries = dayAsync.valueOrNull?.entries ?? const <FoodLogItemModel>[];

    final now = DateTime.now();
    final isToday = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;
    final headerTitle = isToday
        ? 'AUJOURD’HUI'
        : DateFormat('EEE d MMM', 'fr_FR').format(selectedDate).toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(headerTitle),
        actions: [
          IconButton(
            tooltip: 'Choisir une date',
            icon: const Icon(LucideIcons.calendar, size: 20),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
                locale: const Locale('fr', 'FR'),
              );
              if (picked != null) {
                _changeDate(picked);
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.moreVertical),
            color: AppColors.surfaceElevated,
            onSelected: (value) {
              if (value == 'copy_to') {
                _copyToTargetDate(context, ref, selectedDate);
              } else if (value == 'copy_yesterday') {
                _duplicateYesterdayHere(context, ref, selectedDate);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'copy_to',
                child: Text('Copier cette journée vers...'),
              ),
              PopupMenuItem(
                value: 'copy_yesterday',
                child: Text('Dupliquer la journée d’hier ici'),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                color: AppColors.background,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Column(
                  children: [
                    WeekDateStrip(
                      selectedDate: selectedDate,
                      showHeaderRow: true,
                      onDateSelected: _changeDate,
                    ),
                    const SizedBox(height: 10),
                    dayAsync.whenOrNull(
                          data: (day) => _StickyMacroHeader(day: day),
                        ) ??
                        const SizedBox(height: 32),
                  ],
                ),
              ),
              if (_pendingBatchAction != null)
                _PendingBatchBanner(
                  action: _pendingBatchAction!,
                  count: _pendingLogIds.length,
                  onCancel: _cancelPendingBatchAction,
                ),
              const Divider(),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) => _dragDistanceX = 0,
                  onHorizontalDragUpdate: (details) =>
                      _dragDistanceX += details.delta.dx,
                  onHorizontalDragCancel: () => _dragDistanceX = 0,
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity > 300 || _dragDistanceX > 65) {
                      _changeDate(
                        selectedDate.subtract(const Duration(days: 1)),
                      );
                    } else if (velocity < -300 || _dragDistanceX < -65) {
                      _changeDate(selectedDate.add(const Duration(days: 1)));
                    }
                    _dragDistanceX = 0;
                  },
                  child: RefreshIndicator(
                    color: AppColors.calories,
                    backgroundColor: AppColors.surface,
                    onRefresh: () => ref.refresh(journalDayProvider.future),
                    child: dayAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.calories,
                        ),
                      ),
                      error: (error, _) => ListView(
                        padding: const EdgeInsets.all(20),
                        children: [Text('Erreur : $error')],
                      ),
                      data: (day) {
                        final dateKey = ValueKey(
                          DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                          ),
                        );
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, animation) {
                            final isIncoming = child.key == dateKey;
                            final beginOffset = isIncoming
                                ? Offset(0.18 * _daySlideDirection, 0)
                                : Offset(-0.18 * _daySlideDirection, 0);
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
                          child: _HourlyTimelineList(
                            key: dateKey,
                            selectedDate: selectedDate,
                            entries: day.entries,
                            selectedIds: _selectedIds,
                            pendingAction: _pendingBatchAction,
                            isCompact: isCompact,
                            onAddAtHour: (hour) {
                              if (_pendingBatchAction != null) {
                                _executePendingAtHour(selectedDate, hour);
                              } else {
                                openFoodLoggerSheet(
                                  context,
                                  targetDate: selectedDate,
                                  initialTime: TimeOfDay(hour: hour, minute: 0),
                                );
                              }
                            },
                            onToggleSelect: (item) =>
                                _toggleSelection(item.id),
                            onEditItem: (item) =>
                                _openEditLogSheet(context, ref, item),
                            onDeleteItem: (item) async {
                              setState(() => _selectedIds.remove(item.id));
                              final error = await ref
                                  .read(journalDayProvider.notifier)
                                  .optimisticDelete(item.id);
                              if (error != null && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(error),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_selectedIds.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: _BatchActionsBar(
                selectedCount: _selectedIds.length,
                allSelected:
                    entries.isNotEmpty && _selectedIds.length == entries.length,
                onToggleSelectAll: () => _toggleSelectAll(entries),
                onEditSingle: _selectedIds.length == 1
                    ? () {
                        final id = _selectedIds.first;
                        final match = entries.where((e) => e.id == id);
                        if (match.isNotEmpty) {
                          _openEditLogSheet(context, ref, match.first);
                        }
                      }
                    : null,
                onCopy: () => _startPendingBatchAction(BatchActionType.copy),
                onMove: () => _startPendingBatchAction(BatchActionType.move),
                onMultiDateCopy: () => _openMultiDateCopy(selectedDate),
                onDelete: _batchDelete,
              ),
            ),
        ],
      ),
    );
  }
}

class _PendingBatchBanner extends StatelessWidget {
  const _PendingBatchBanner({
    required this.action,
    required this.count,
    required this.onCancel,
  });

  final BatchActionType action;
  final int count;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isCopy = action == BatchActionType.copy;
    final color = isCopy ? AppColors.calories : AppColors.weight;
    final verb = isCopy ? 'copier' : 'déplacer';

    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(
            isCopy ? LucideIcons.copy : LucideIcons.arrowRightLeft,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count aliment(s) à $verb — naviguez vers le jour voulu et cliquez sur une flèche horaire',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Annuler',
            onPressed: onCancel,
            icon: Icon(LucideIcons.x, size: 18, color: color),
          ),
        ],
      ),
    );
  }
}

class _StickyMacroHeader extends StatelessWidget {
  const _StickyMacroHeader({required this.day});

  final DayLogsModel day;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 13,
          child: _MiniMacroBar(
            icon: LucideIcons.flame,
            prefix: '',
            consumed: day.totals.kcal,
            target: day.targets.kcal,
            color: AppColors.calories,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 10,
          child: _MiniMacroBar(
            prefix: 'P',
            consumed: day.totals.proteinG,
            target: day.targets.proteinG,
            color: AppColors.protein,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 10,
          child: _MiniMacroBar(
            prefix: 'L',
            consumed: day.totals.fatG,
            target: day.targets.fatG,
            color: AppColors.fat,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 10,
          child: _MiniMacroBar(
            prefix: 'G',
            consumed: day.totals.carbsG,
            target: day.targets.carbsG,
            color: AppColors.carbs,
          ),
        ),
      ],
    );
  }
}

class _MiniMacroBar extends StatelessWidget {
  const _MiniMacroBar({
    this.icon,
    required this.prefix,
    required this.consumed,
    required this.target,
    required this.color,
  });

  final IconData? icon;
  final String prefix;
  final double consumed;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safeTarget = target <= 0 ? 1.0 : target;
    final ratio = (consumed / safeTarget).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 3),
              ],
              if (prefix.isNotEmpty) ...[
                Text(
                  '$prefix ',
                  style: AppTheme.numericStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
              Text(
                '${consumed.round()}/${target.round()}',
                style: AppTheme.numericStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: AppColors.surfaceElevated,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _HourlyTimelineList extends StatelessWidget {
  const _HourlyTimelineList({
    super.key,
    required this.selectedDate,
    required this.entries,
    required this.selectedIds,
    required this.pendingAction,
    required this.isCompact,
    required this.onAddAtHour,
    required this.onToggleSelect,
    required this.onEditItem,
    required this.onDeleteItem,
  });

  final DateTime selectedDate;
  final List<FoodLogItemModel> entries;
  final Set<String> selectedIds;
  final BatchActionType? pendingAction;
  final bool isCompact;
  final ValueChanged<int> onAddAtHour;
  final ValueChanged<FoodLogItemModel> onToggleSelect;
  final ValueChanged<FoodLogItemModel> onEditItem;
  final Future<void> Function(FoodLogItemModel) onDeleteItem;

  @override
  Widget build(BuildContext context) {
    final grouped = <int, List<FoodLogItemModel>>{};
    for (final item in entries) {
      final hour = int.tryParse(item.loggedTime.split(':').first) ?? 12;
      grouped.putIfAbsent(hour, () => []).add(item);
    }

    final hoursSet = <int>{
      for (var h = 7; h <= 22; h++) h,
      ...grouped.keys,
    };
    final hours = hoursSet.toList()..sort();

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        12,
        isCompact ? 8 : 12,
        14,
        selectedIds.isNotEmpty ? 84 : 24,
      ),
      itemCount: hours.length,
      itemBuilder: (context, index) {
        final hour = hours[index];
        final hourEntries = grouped[hour] ?? const [];
        final hourLabel = '${hour.toString().padLeft(2, '0')}:00';

        final hourKcal = hourEntries.fold<double>(0, (s, e) => s + e.kcal);
        final hourP = hourEntries.fold<double>(0, (s, e) => s + e.proteinG);
        final hourF = hourEntries.fold<double>(0, (s, e) => s + e.fatG);
        final hourC = hourEntries.fold<double>(0, (s, e) => s + e.carbsG);

        final actionColor = pendingAction == BatchActionType.move
            ? AppColors.weight
            : AppColors.calories;

        return Padding(
          padding: EdgeInsets.only(bottom: isCompact ? 4 : 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 8 : 10,
                      vertical: isCompact ? 2 : 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      hourLabel,
                      style: AppTheme.numericStyle(
                        fontSize: isCompact ? 11 : 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => onAddAtHour(hour),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: isCompact ? 22 : 24,
                      height: isCompact ? 22 : 24,
                      decoration: BoxDecoration(
                        color: pendingAction != null
                            ? actionColor.withValues(alpha: 0.2)
                            : AppColors.surfaceElevated,
                        shape: BoxShape.circle,
                        border: pendingAction != null
                            ? Border.all(color: actionColor, width: 1.2)
                            : null,
                      ),
                      child: Icon(
                        pendingAction != null
                            ? LucideIcons.arrowRight
                            : LucideIcons.plus,
                        size: 13,
                        color: pendingAction != null
                            ? actionColor
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (hourEntries.isNotEmpty)
                    Text(
                      '${hourKcal.round()} kcal · ${hourP.round()}P · ${hourF.round()}L · ${hourC.round()}G',
                      style: AppTheme.numericStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
              if (hourEntries.isNotEmpty) ...[
                SizedBox(height: isCompact ? 4 : 8),
                ...hourEntries.map(
                  (item) {
                    final isSelected = selectedIds.contains(item.id);
                    return Padding(
                      padding: EdgeInsets.only(
                        left: isCompact ? 34 : 44,
                        bottom: isCompact ? 4 : 8,
                      ),
                      child: Dismissible(
                        key: ValueKey(item.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 18),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            LucideIcons.trash2,
                            color: AppColors.error,
                            size: 20,
                          ),
                        ),
                        onDismissed: (_) => onDeleteItem(item),
                        child: InkWell(
                          onTap: () => onToggleSelect(item),
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 10 : 12,
                              vertical: isCompact ? 5 : 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.calories.withValues(alpha: 0.10)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(
                                isCompact ? 11 : 14,
                              ),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.calories
                                    : AppColors.border,
                                width: isSelected ? 1.6 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                if (!isCompact || isSelected) ...[
                                  Container(
                                    width: isCompact ? 22 : 32,
                                    height: isCompact ? 22 : 32,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.calories
                                          : AppColors.surfaceElevated,
                                      borderRadius: BorderRadius.circular(
                                        isCompact ? 7 : 10,
                                      ),
                                    ),
                                    child: Icon(
                                      isSelected
                                          ? LucideIcons.check
                                          : LucideIcons.utensils,
                                      size: isCompact ? 13 : 15,
                                      color: isSelected
                                          ? AppColors.background
                                          : AppColors.calories,
                                    ),
                                  ),
                                  SizedBox(width: isCompact ? 8 : 10),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(height: isCompact ? 1 : 3),
                                      if (isCompact)
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text.rich(
                                            TextSpan(
                                              style: AppTheme.numericStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                              ),
                                              children: [
                                                TextSpan(
                                                  text:
                                                      '${item.kcal.round()} kcal',
                                                  style: const TextStyle(
                                                    color: AppColors.calories,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const TextSpan(text: ' · '),
                                                TextSpan(
                                                  text:
                                                      '${item.proteinG.round()}P',
                                                  style: const TextStyle(
                                                    color: AppColors.protein,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const TextSpan(text: ' '),
                                                TextSpan(
                                                  text: '${item.fatG.round()}L',
                                                  style: const TextStyle(
                                                    color: AppColors.fat,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const TextSpan(text: ' '),
                                                TextSpan(
                                                  text:
                                                      '${item.carbsG.round()}G',
                                                  style: const TextStyle(
                                                    color: AppColors.carbs,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text:
                                                      ' · ${item.quantityG.round()} g',
                                                  style: const TextStyle(
                                                    color: AppColors.textMuted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            maxLines: 1,
                                          ),
                                        )
                                      else
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '${item.kcal.round()} kcal',
                                                style: AppTheme.numericStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.calories,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              _MacroBadge(
                                                text:
                                                    '${item.proteinG.round()}P',
                                                color: AppColors.protein,
                                              ),
                                              const SizedBox(width: 4),
                                              _MacroBadge(
                                                text: '${item.fatG.round()}L',
                                                color: AppColors.fat,
                                              ),
                                              const SizedBox(width: 4),
                                              _MacroBadge(
                                                text:
                                                    '${item.carbsG.round()}G',
                                                color: AppColors.carbs,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '· ${item.quantityG.round()}g',
                                                style: AppTheme.numericStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: isCompact
                                      ? EdgeInsets.zero
                                      : const EdgeInsets.all(6),
                                  constraints:
                                      isCompact ? const BoxConstraints() : null,
                                  tooltip: 'Modifier',
                                  onPressed: () => onEditItem(item),
                                  icon: Icon(
                                    LucideIcons.pencil,
                                    size: 16,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MacroBadge extends StatelessWidget {
  const _MacroBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: AppTheme.numericStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _BatchActionsBar extends StatelessWidget {
  const _BatchActionsBar({
    required this.selectedCount,
    required this.allSelected,
    required this.onToggleSelectAll,
    this.onEditSingle,
    required this.onCopy,
    required this.onMove,
    required this.onMultiDateCopy,
    required this.onDelete,
  });

  final int selectedCount;
  final bool allSelected;
  final VoidCallback onToggleSelectAll;
  final VoidCallback? onEditSingle;
  final VoidCallback onCopy;
  final VoidCallback onMove;
  final VoidCallback onMultiDateCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.calories, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            Text(
              '$selectedCount sélect.',
              style: AppTheme.numericStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.calories,
              ),
            ),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: allSelected ? 'Désélectionner tout' : 'Tout sélectionner',
              onPressed: onToggleSelectAll,
              icon: Icon(
                LucideIcons.checkCheck,
                size: 18,
                color: allSelected ? AppColors.calories : AppColors.textPrimary,
              ),
            ),
            if (onEditSingle != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Éditer',
                onPressed: onEditSingle,
                icon: const Icon(LucideIcons.pencil, size: 17),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Copier',
              onPressed: onCopy,
              icon: const Icon(LucideIcons.copy, size: 17),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Déplacer',
              onPressed: onMove,
              icon: const Icon(LucideIcons.arrowRightLeft, size: 17),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Copier vers plusieurs dates',
              onPressed: onMultiDateCopy,
              icon: const Icon(LucideIcons.calendarPlus, size: 17),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Supprimer',
              onPressed: onDelete,
              icon: const Icon(
                LucideIcons.trash2,
                size: 17,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MultiDatePickerDialog extends StatefulWidget {
  const _MultiDatePickerDialog({required this.initialMonth});

  final DateTime initialMonth;

  @override
  State<_MultiDatePickerDialog> createState() => _MultiDatePickerDialogState();
}

class _MultiDatePickerDialogState extends State<_MultiDatePickerDialog> {
  late DateTime _focusedMonth;
  final Set<DateTime> _selectedDates = {};

  @override
  void initState() {
    super.initState();
    _focusedMonth = DateTime(widget.initialMonth.year, widget.initialMonth.month);
  }

  void _toggleDate(DateTime d) {
    final norm = DateTime(d.year, d.month, d.day);
    setState(() {
      if (_selectedDates.contains(norm)) {
        _selectedDates.remove(norm);
      } else {
        _selectedDates.add(norm);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final nextMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
    final daysInMonth = nextMonth.subtract(const Duration(days: 1)).day;
    final leadingBlanks = monthStart.weekday - 1;
    final totalCells = leadingBlanks + daysInMonth;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Copie multi-dates'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month - 1,
                      );
                    });
                  },
                  icon: const Icon(LucideIcons.chevronLeft, size: 18),
                ),
                Text(
                  DateFormat('MMMM yyyy', 'fr_FR')
                      .format(monthStart)
                      .toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month + 1,
                      );
                    });
                  },
                  icon: const Icon(LucideIcons.chevronRight, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('L', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                Text('M', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                Text('M', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                Text('J', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                Text('V', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                Text('S', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                Text('D', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: totalCells,
              itemBuilder: (_, idx) {
                if (idx < leadingBlanks) return const SizedBox.shrink();
                final dayNum = idx - leadingBlanks + 1;
                final dayDate = DateTime(
                  monthStart.year,
                  monthStart.month,
                  dayNum,
                );
                final selected = _selectedDates.contains(dayDate);

                return InkWell(
                  onTap: () => _toggleDate(dayDate),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.calories
                          : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? AppColors.calories : AppColors.border,
                      ),
                    ),
                    child: Text(
                      '$dayNum',
                      style: AppTheme.numericStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppColors.background
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _selectedDates.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selectedDates),
          child: Text('Copier vers ${_selectedDates.length} jour(s)'),
        ),
      ],
    );
  }
}

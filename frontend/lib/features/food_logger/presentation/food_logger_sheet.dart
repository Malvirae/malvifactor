import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/core/widgets/food_category_avatar.dart';
import 'package:malvifactor/core/widgets/pressable_scale.dart';
import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/food_logger/presentation/barcode_review_sheet.dart';
import 'package:malvifactor/features/food_logger/presentation/barcode_scanner_screen.dart';
import 'package:malvifactor/features/food_logger/presentation/quantity_bottom_sheet.dart';
import 'package:malvifactor/features/food_logger/presentation/widgets/food_search_widgets.dart';
import 'package:malvifactor/features/food_logger/presentation/widgets/recipe_portion_input.dart';
import 'package:malvifactor/features/food_logger/providers/food_basket_provider.dart';
import 'package:malvifactor/features/journal/presentation/journal_screen.dart';
import 'package:malvifactor/features/profile/providers/profile_provider.dart';
import 'package:malvifactor/features/recipes/data/recipe_repository.dart';
import 'package:malvifactor/features/recipes/presentation/recipe_editor_screen.dart';

Future<void> openFoodLoggerSheet(
  BuildContext context, {
  required DateTime targetDate,
  TimeOfDay? initialTime,
  bool openScannerDirectly = false,
  bool autoFocusSearch = false,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => FoodLoggerSheet(
      targetDate: targetDate,
      initialTime: initialTime,
      openScannerDirectly: openScannerDirectly,
      autoFocusSearch: autoFocusSearch,
    ),
  );
}

class FoodLoggerSheet extends ConsumerStatefulWidget {
  const FoodLoggerSheet({
    super.key,
    required this.targetDate,
    this.initialTime,
    this.openScannerDirectly = false,
    this.autoFocusSearch = false,
  });

  final DateTime targetDate;
  final TimeOfDay? initialTime;
  final bool openScannerDirectly;
  final bool autoFocusSearch;

  @override
  ConsumerState<FoodLoggerSheet> createState() => _FoodLoggerSheetState();
}

class _FoodLoggerSheetState extends ConsumerState<FoodLoggerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final _quickNameController = TextEditingController();
  final _quickKcalController = TextEditingController(text: '0');
  final _quickProteinController = TextEditingController(text: '0');
  final _quickFatController = TextEditingController(text: '0');
  final _quickCarbsController = TextEditingController(text: '0');

  final _quickKcalFocusNode = FocusNode();
  final _quickProteinFocusNode = FocusNode();
  final _quickFatFocusNode = FocusNode();
  final _quickCarbsFocusNode = FocusNode();

  Timer? _localDebounce;
  Timer? _offDebounce;
  int _searchSeq = 0;
  int _tabIndex = 0; // 0: Recherche, 1: Recettes, 2: Ajout libre
  GroupedFoodSectionModel _historySection = GroupedFoodSectionModel.empty;
  GroupedFoodSectionModel _customSection = GroupedFoodSectionModel.empty;
  GroupedFoodSectionModel _commonSection = GroupedFoodSectionModel.empty;
  GroupedFoodSectionModel _offSection = GroupedFoodSectionModel.empty;
  final Set<String> _expandedSections = <String>{};
  bool _loadingLocal = false;
  bool _loadingOff = false;
  bool _submittingQuick = false;
  bool _basketExpanded = false;

  double _alreadyLoggedKcal = 0.0;
  double _dayCalorieTarget = 2000.0;

  void _attachSelectAllOnFocus(
    FocusNode node,
    TextEditingController controller,
  ) {
    node.addListener(() {
      if (node.hasFocus && controller.text.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (node.hasFocus && controller.text.isNotEmpty) {
            controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: controller.text.length,
            );
          }
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final initialHour = (widget.initialTime ?? TimeOfDay.now()).hour;
    _attachSelectAllOnFocus(_quickKcalFocusNode, _quickKcalController);
    _attachSelectAllOnFocus(_quickProteinFocusNode, _quickProteinController);
    _attachSelectAllOnFocus(_quickFatFocusNode, _quickFatController);
    _attachSelectAllOnFocus(_quickCarbsFocusNode, _quickCarbsController);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(foodBasketProvider.notifier)
          .initSession(widget.targetDate, initialHour);
      _loadDayCaloriesContext();
      if (widget.openScannerDirectly) {
        _openBarcodeScanner();
      } else if (widget.autoFocusSearch) {
        Future<void>.delayed(const Duration(milliseconds: 180), () {
          if (!mounted || _tabIndex != 0) return;
          _searchFocusNode.requestFocus();
          SystemChannels.textInput.invokeMethod<void>('TextInput.show');
        });
      }
    });
  }

  Future<void> _loadDayCaloriesContext() async {
    final fallbackTarget =
        ref.read(profileProvider).valueOrNull?.currentCalorieTarget ?? 2000.0;
    if (mounted) {
      setState(() => _dayCalorieTarget = fallbackTarget);
    }
    try {
      final day = await ref
          .read(dashboardRepositoryProvider)
          .fetchDayLogs(widget.targetDate);
      if (!mounted) return;
      setState(() {
        _alreadyLoggedKcal = day.totals.kcal;
        _dayCalorieTarget =
            day.targets.kcal > 0 ? day.targets.kcal : fallbackTarget;
      });
    } catch (_) {
      // Keep fallback target silently.
    }
  }

  @override
  void dispose() {
    _localDebounce?.cancel();
    _offDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _quickNameController.dispose();
    _quickKcalController.dispose();
    _quickProteinController.dispose();
    _quickFatController.dispose();
    _quickCarbsController.dispose();
    _quickKcalFocusNode.dispose();
    _quickProteinFocusNode.dispose();
    _quickFatFocusNode.dispose();
    _quickCarbsFocusNode.dispose();
    super.dispose();
  }

  void _onSearchQueryChanged(String value) {
    final trimmed = value.trim();
    _localDebounce?.cancel();
    _offDebounce?.cancel();
    _searchSeq += 1;
    final seq = _searchSeq;

    setState(() {
      _expandedSections.clear();
      if (_tabIndex == 2 && trimmed.isNotEmpty) {
        _tabIndex = 0;
      }
      if (trimmed.length < 2) {
        _historySection = GroupedFoodSectionModel.empty;
        _customSection = GroupedFoodSectionModel.empty;
        _commonSection = GroupedFoodSectionModel.empty;
        _offSection = GroupedFoodSectionModel.empty;
        _loadingLocal = false;
        _loadingOff = false;
      } else {
        _loadingLocal = true;
        _loadingOff = true;
        _offSection = GroupedFoodSectionModel.empty;
      }
    });

    if (trimmed.length < 2) return;

    _localDebounce = Timer(const Duration(milliseconds: 150), () {
      _fetchGroupedScope(trimmed, scope: 'local', seq: seq);
    });
    _offDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchGroupedScope(trimmed, scope: 'off', seq: seq);
    });
  }

  Future<void> _fetchGroupedScope(
    String query, {
    required String scope,
    required int seq,
  }) async {
    try {
      final res = await ref.read(foodRepositoryProvider).searchFoodsGrouped(
            query,
            scope: scope,
            limitPerGroup: 25,
          );
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        if (scope == 'local') {
          _historySection = res.history ?? GroupedFoodSectionModel.empty;
          _customSection = res.custom ?? GroupedFoodSectionModel.empty;
          _commonSection = res.common ?? GroupedFoodSectionModel.empty;
          _loadingLocal = false;
        } else {
          _offSection = res.openfoodfacts ?? GroupedFoodSectionModel.empty;
          _loadingOff = false;
        }
      });
    } catch (_) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        if (scope == 'local') {
          _loadingLocal = false;
        } else {
          _loadingOff = false;
        }
      });
    }
  }

  Future<void> _handleClose() async {
    final basket = ref.read(foodBasketProvider);
    if (basket.items.isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Vider le panier en cours ?'),
        content: Text(
          'Vous avez ${basket.itemCount} élément${basket.itemCount > 1 ? 's' : ''} non enregistré${basket.itemCount > 1 ? 's' : ''} dans votre assiette.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continuer'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.textPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Vider et fermer'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      ref.read(foodBasketProvider.notifier).clearBasket();
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickTargetHour(int currentHour) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Heure du repas'),
        content: SizedBox(
          width: 300,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.9,
            ),
            itemCount: 24,
            itemBuilder: (_, h) {
              final selected = h == currentHour;
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(ctx).pop(h),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.calories
                        : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? AppColors.calories : AppColors.border,
                    ),
                  ),
                  child: Text(
                    '${h.toString().padLeft(2, '0')}:00',
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
        ),
      ),
    );

    if (picked != null && mounted) {
      ref.read(foodBasketProvider.notifier).setTargetHour(picked);
    }
  }

  Future<void> _openBarcodeScanner() async {
    final food = await Navigator.of(context).push<FoodModel>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (food == null || !mounted) return;

    final reviewed = await showModalBottomSheet<FoodModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => BarcodeReviewSheet(food: food),
    );
    if (reviewed != null && mounted) {
      await _openQuantitySheet(
        food: reviewed,
        initialQuantityG: reviewed.defaultQuantityG,
      );
    }
  }

  Future<void> _openQuantitySheet({
    FoodModel? food,
    RecipeSummaryModel? recipe,
    double? initialQuantityG,
  }) async {
    final basketHour = ref.read(foodBasketProvider).targetHour;
    final outcome = await showModalBottomSheet<QuantitySheetOutcome>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => QuantityBottomSheet(
        targetDate: widget.targetDate,
        initialTime: TimeOfDay(hour: basketHour, minute: 0),
        initialQuantityG: initialQuantityG,
        food: food,
        recipe: recipe,
      ),
    );
    if (!mounted) return;
    if (outcome == QuantitySheetOutcome.loggedSingle &&
        ref.read(foodBasketProvider).items.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openCreateCustomFoodDialog() async {
    final nameCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final kcalCtrl = TextEditingController();
    final pCtrl = TextEditingController(text: '0');
    final fCtrl = TextEditingController(text: '0');
    final cCtrl = TextEditingController(text: '0');

    final created = await showDialog<FoodModel>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Créer un aliment perso (100g)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: brandCtrl,
                decoration:
                    const InputDecoration(labelText: 'Marque (optionnel)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: kcalCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Calories / 100g'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: pCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'P (g)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: fCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'L (g)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: cCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'G (g)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final food =
                  await ref.read(foodRepositoryProvider).createCustomFood(
                        name: nameCtrl.text.trim(),
                        brand: brandCtrl.text.trim(),
                        kcalPer100g: double.tryParse(
                              kcalCtrl.text.replaceAll(',', '.'),
                            ) ??
                            0,
                        proteinPer100g: double.tryParse(
                              pCtrl.text.replaceAll(',', '.'),
                            ) ??
                            0,
                        fatPer100g: double.tryParse(
                              fCtrl.text.replaceAll(',', '.'),
                            ) ??
                            0,
                        carbsPer100g: double.tryParse(
                              cCtrl.text.replaceAll(',', '.'),
                            ) ??
                            0,
                      );
              if (ctx.mounted) Navigator.of(ctx).pop(food);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    if (created != null && mounted) {
      await _openQuantitySheet(food: created);
    }
  }

  Future<void> _editBasketItemQuantity(BasketItem item) async {
    if (item.isQuickAdd) return;
    double draftQtyG = item.quantityG;

    final newQty = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final factor = draftQtyG / 100.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (item.itemType == 'recipe') ...[
                      const SizedBox(width: 8),
                      const FoodSourceBadge(source: 'recipe'),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                ColoredMacroInlineRow(
                  prefix: 'Portion : ',
                  kcal: item.kcalPer100g * factor,
                  proteinG: item.proteinPer100g * factor,
                  fatG: item.fatPer100g * factor,
                  carbsG: item.carbsPer100g * factor,
                  fontSize: 13.5,
                ),
                const SizedBox(height: 14),
                PortionAwareQuantitySection(
                  initialQuantityG: item.quantityG,
                  servingWeightG: item.recipeServingWeightG,
                  totalWeightG: item.recipeTotalWeightG,
                  servingsCount: item.recipeServings,
                  autofocus: true,
                  onQuantityChanged: (g) => setModalState(() => draftQtyG = g),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: draftQtyG > 0
                      ? () => Navigator.of(ctx).pop(draftQtyG)
                      : null,
                  child: const Text('Valider'),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (newQty != null && newQty > 0) {
      ref
          .read(foodBasketProvider.notifier)
          .updateItemQuantity(item.localId, newQty);
    }
  }

  Future<void> _submitQuickAddToBasket({required bool logAlone}) async {
    final name = _quickNameController.text.trim();
    final kcal =
        double.tryParse(_quickKcalController.text.replaceAll(',', '.'));
    if (name.isEmpty || kcal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nom et calories requis pour l’ajout libre.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final protein =
        double.tryParse(_quickProteinController.text.replaceAll(',', '.')) ??
            0;
    final fat =
        double.tryParse(_quickFatController.text.replaceAll(',', '.')) ?? 0;
    final carbs =
        double.tryParse(_quickCarbsController.text.replaceAll(',', '.')) ?? 0;

    if (!logAlone) {
      HapticFeedback.lightImpact();
      ref.read(foodBasketProvider.notifier).addQuickAdd(
            name: name,
            kcal: kcal,
            proteinG: protein,
            fatG: fat,
            carbsG: carbs,
          );
      _quickNameController.clear();
      _quickKcalController.text = '0';
      _quickProteinController.text = '0';
      _quickFatController.text = '0';
      _quickCarbsController.text = '0';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('« $name » ajouté au panier.'),
          duration: const Duration(milliseconds: 1400),
          backgroundColor: AppColors.surfaceElevated,
        ),
      );
      return;
    }

    setState(() => _submittingQuick = true);
    try {
      final hour = ref.read(foodBasketProvider).targetHour;
      await ref.read(foodRepositoryProvider).logQuickAdd(
            loggedDate: widget.targetDate,
            loggedTime: TimeOfDay(hour: hour, minute: 0),
            customName: name,
            kcal: kcal,
            proteinG: protein,
            fatG: fat,
            carbsG: carbs,
          );
      ref.invalidate(dashboardProvider);
      ref.invalidate(journalDayProvider);
      ref.invalidate(fullMetricContextProvider);
      ref.invalidate(foodSuggestionsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submittingQuick = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _submitBasket() async {
    final error = await ref.read(foodBasketProvider.notifier).submitBasket();
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de l’enregistrement : $error'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final basket = ref.watch(foodBasketProvider);
    final recipesAsync = ref.watch(recipesListProvider(_searchController.text));
    final suggestionsAsync = ref.watch(foodSuggestionsProvider(basket.targetHour));

    return PopScope(
      canPop: basket.items.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleClose();
        }
      },
      child: SafeArea(
        top: true,
        bottom: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.94,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top dynamic header pills
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(
                    children: [
                      // Close X pill
                      _HeaderPillButton(
                        onTap: _handleClose,
                        child: const Icon(
                          LucideIcons.x,
                          size: 18,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Hour selector pill
                      _HeaderPillButton(
                        onTap: () => _pickTargetHour(basket.targetHour),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.clock,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${basket.targetHour.toString().padLeft(2, '0')}:00',
                              style: AppTheme.numericStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Live Calorie Gauge pill (isolated with .select)
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final basketKcal = ref.watch(
                              foodBasketProvider.select((b) => b.totalKcal),
                            );
                            final basketCount = ref.watch(
                              foodBasketProvider.select((b) => b.itemCount),
                            );
                            final projected = _alreadyLoggedKcal + basketKcal;
                            final safeT = _dayCalorieTarget <= 0
                                ? 2000.0
                                : _dayCalorieTarget;
                            final ratio = (projected / safeT).clamp(0.0, 1.0);
                            return Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: basketCount > 0
                                      ? AppColors.calories
                                          .withValues(alpha: 0.7)
                                      : AppColors.border,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '${projected.round()} / ${safeT.round()} kcal',
                                      style: AppTheme.numericStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  AnimatedMacroBar(
                                    value: ratio,
                                    color: AppColors.calories,
                                    minHeight: 3.5,
                                    backgroundColor: AppColors.border,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Plate / Basket toggle pill (isolated with .select)
                      Consumer(
                        builder: (context, ref, _) {
                          final itemCount = ref.watch(
                            foodBasketProvider.select((b) => b.itemCount),
                          );
                          final disableAnim =
                              MediaQuery.disableAnimationsOf(context);
                          return _HeaderPillButton(
                            highlighted: itemCount > 0 || _basketExpanded,
                            onTap: () => setState(
                              () => _basketExpanded = !_basketExpanded,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.utensils,
                                  size: 15,
                                  color: itemCount > 0
                                      ? AppColors.calories
                                      : AppColors.textSecondary,
                                ),
                                if (itemCount > 0) ...[
                                  const SizedBox(width: 5),
                                  AnimatedSwitcher(
                                    duration: disableAnim
                                        ? Duration.zero
                                        : const Duration(milliseconds: 200),
                                    transitionBuilder: (child, anim) =>
                                        ScaleTransition(
                                      scale: CurvedAnimation(
                                        parent: anim,
                                        curve: Curves.easeOutBack,
                                      ),
                                      child: child,
                                    ),
                                    child: Container(
                                      key: ValueKey<int>(itemCount),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.calories,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '$itemCount',
                                        style: AppTheme.numericStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.background,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 3),
                                Icon(
                                  _basketExpanded
                                      ? LucideIcons.chevronUp
                                      : LucideIcons.chevronDown,
                                  size: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Expandable Plate / Basket Drawer
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: _basketExpanded
                      ? _BasketDrawer(
                          basket: basket,
                          onEditItem: _editBasketItemQuantity,
                          onRemoveItem: (id) => ref
                              .read(foodBasketProvider.notifier)
                              .removeItem(id),
                          onClear: () => ref
                              .read(foodBasketProvider.notifier)
                              .clearBasket(),
                        )
                      : const SizedBox.shrink(),
                ),

                // Mode Tabs (Recherche / Recettes / Ajout libre) + + Perso
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            padding: WidgetStatePropertyAll(
                              EdgeInsets.symmetric(horizontal: 6),
                            ),
                          ),
                          segments: const [
                            ButtonSegment(
                              value: 0,
                              label: Text(
                                'Recherche',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: Text(
                                'Recettes',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ButtonSegment(
                              value: 2,
                              label: Text(
                                'Ajout libre',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          selected: {_tabIndex},
                          onSelectionChanged: (sel) =>
                              setState(() => _tabIndex = sel.first),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Créer un aliment perso',
                        onPressed: _openCreateCustomFoodDialog,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surfaceElevated,
                          side: const BorderSide(color: AppColors.border),
                        ),
                        icon: const Icon(LucideIcons.plus, size: 17),
                      ),
                    ],
                  ),
                ),

                // Main Scrollable Body (edge-to-edge hairline rows for Recherche & Recettes)
                Expanded(
                  child: switch (_tabIndex) {
                    0 => _buildSearchOrSuggestionsTab(
                        suggestionsAsync: suggestionsAsync,
                        basket: basket,
                      ),
                    1 => _buildRecipesTab(recipesAsync, basket),
                    _ => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: _buildQuickAddTab(),
                      ),
                  },
                ),

                // Fixed Bottom Action Bar: Search Input + White Logger (X) pill
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          autofocus: widget.autoFocusSearch && _tabIndex == 0,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Rechercher un aliment...',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: const BorderSide(
                                color: AppColors.calories,
                                width: 1.5,
                              ),
                            ),
                            prefixIcon: const Icon(LucideIcons.search, size: 17),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_searchController.text.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Effacer',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      _searchController.clear();
                                      _onSearchQueryChanged('');
                                    },
                                    icon: const Icon(LucideIcons.x, size: 16),
                                  ),
                                IconButton(
                                  tooltip: 'Scanner un code-barres',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _openBarcodeScanner,
                                  icon: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                    size: 19,
                                    color: AppColors.calories,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onChanged: _onSearchQueryChanged,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Consumer(
                        builder: (context, ref, _) {
                          final itemCount = ref.watch(
                            foodBasketProvider.select((b) => b.itemCount),
                          );
                          final isSubmitting = ref.watch(
                            foodBasketProvider.select((b) => b.isSubmitting),
                          );
                          final disableAnim =
                              MediaQuery.disableAnimationsOf(context);
                          return ElevatedButton(
                            onPressed: itemCount == 0 || isSubmitting
                                ? null
                                : _submitBasket,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF8FAFC),
                              foregroundColor: AppColors.background,
                              disabledBackgroundColor:
                                  AppColors.surfaceElevated,
                              disabledForegroundColor: AppColors.textMuted,
                              minimumSize: const Size(106, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.background,
                                    ),
                                  )
                                : AnimatedSwitcher(
                                    duration: disableAnim
                                        ? Duration.zero
                                        : const Duration(milliseconds: 180),
                                    transitionBuilder: (child, anim) =>
                                        ScaleTransition(
                                      scale: Tween<double>(begin: 0.86, end: 1.0)
                                          .animate(
                                        CurvedAnimation(
                                          parent: anim,
                                          curve: Curves.easeOutBack,
                                        ),
                                      ),
                                      child: FadeTransition(
                                        opacity: anim,
                                        child: child,
                                      ),
                                    ),
                                    child: Text(
                                      itemCount > 0
                                          ? 'Logger ($itemCount)'
                                          : 'Logger',
                                      key: ValueKey<int>(itemCount),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupedRow(GroupedFoodItemModel item, FoodBasketState basket) {
    final qty = item.defaultQuantityG;
    final count = item.isQuickAdd
        ? basket.countFor(quickName: item.name)
        : (item.isRecipe
            ? basket.countFor(recipeId: item.id)
            : basket.countFor(foodId: item.id));
    return FoodSearchResultRow(
      key: ValueKey<String>('${item.itemType}_${item.id}'),
      name: item.name,
      brand: item.brand,
      stores: item.stores,
      source: item.source,
      category: item.category,
      quantityG: qty,
      customQuantityText: item.isQuickAdd
          ? 'Ajout libre'
          : (item.isRecipe && item.servingWeightG != null
              ? formatRecipeUnitSubtitle(qty, item.servingWeightG)
              : null),
      kcal: item.previewKcal,
      proteinG: item.previewProteinG,
      fatG: item.previewFatG,
      carbsG: item.previewCarbsG,
      basketCount: count,
      onQuickAdd: () {
        HapticFeedback.lightImpact();
        if (item.isQuickAdd) {
          ref.read(foodBasketProvider.notifier).addQuickAdd(
                name: item.name,
                kcal: item.previewKcal,
                proteinG: item.previewProteinG,
                fatG: item.previewFatG,
                carbsG: item.previewCarbsG,
              );
        } else {
          ref
              .read(foodBasketProvider.notifier)
              .addFood(item.toFoodModel(), quantityG: qty);
        }
      },
      onTapRow: () async {
        if (item.isQuickAdd) {
          setState(() {
            _quickNameController.text = item.name;
            _quickKcalController.text = item.previewKcal
                .toStringAsFixed(item.previewKcal % 1 == 0 ? 0 : 1);
            _quickProteinController.text = item.previewProteinG
                .toStringAsFixed(item.previewProteinG % 1 == 0 ? 0 : 1);
            _quickFatController.text = item.previewFatG
                .toStringAsFixed(item.previewFatG % 1 == 0 ? 0 : 1);
            _quickCarbsController.text = item.previewCarbsG
                .toStringAsFixed(item.previewCarbsG % 1 == 0 ? 0 : 1);
            _tabIndex = 2;
          });
        } else if (item.isRecipe) {
          final detail =
              await ref.read(recipeRepositoryProvider).getRecipe(item.id);
          if (!mounted) return;
          await _openQuantitySheet(
            recipe: detail,
            initialQuantityG: qty,
          );
        } else {
          await _openQuantitySheet(
            food: item.toFoodModel(),
            initialQuantityG: qty,
          );
        }
      },
    );
  }

  Widget _buildSearchOrSuggestionsTab({
    required AsyncValue<FoodSuggestionsResponseModel> suggestionsAsync,
    required FoodBasketState basket,
  }) {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      if (query.length < 2) {
        return const Center(
          child: Text(
            'Tapez au moins 2 caractères pour rechercher...',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        );
      }

      final hasAnyResult = _historySection.items.isNotEmpty ||
          _customSection.items.isNotEmpty ||
          _commonSection.items.isNotEmpty ||
          _offSection.items.isNotEmpty;

      if (_loadingLocal && !hasAnyResult) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          children: const [
            SkeletonPulseBox(height: 50, borderRadius: 10),
            SizedBox(height: 8),
            SkeletonPulseBox(height: 50, borderRadius: 10),
            SizedBox(height: 8),
            SkeletonPulseBox(height: 50, borderRadius: 10),
          ],
        );
      }

      if (!_loadingLocal && !_loadingOff && !hasAnyResult) {
        return const Center(
          child: Text(
            'Aucun aliment trouvé pour cette recherche.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        );
      }

      void toggle(String key) {
        setState(() {
          if (_expandedSections.contains(key)) {
            _expandedSections.remove(key);
          } else {
            _expandedSections.add(key);
          }
        });
      }

      return ListView(
        padding: const EdgeInsets.only(bottom: 14),
        children: [
          GroupedSearchSectionWidget<GroupedFoodItemModel>(
            title: 'Historique',
            items: _historySection.items,
            expanded: _expandedSections.contains('history'),
            onToggleExpanded: () => toggle('history'),
            itemBuilder: (_, item) => _buildGroupedRow(item, basket),
          ),
          GroupedSearchSectionWidget<GroupedFoodItemModel>(
            title: 'Perso & Recettes',
            items: _customSection.items,
            expanded: _expandedSections.contains('custom'),
            onToggleExpanded: () => toggle('custom'),
            itemBuilder: (_, item) => _buildGroupedRow(item, basket),
          ),
          GroupedSearchSectionWidget<GroupedFoodItemModel>(
            title: 'Communs (Ciqual)',
            items: _commonSection.items,
            expanded: _expandedSections.contains('common'),
            onToggleExpanded: () => toggle('common'),
            itemBuilder: (_, item) => _buildGroupedRow(item, basket),
          ),
          GroupedSearchSectionWidget<GroupedFoodItemModel>(
            title: 'Open Food Facts',
            items: _offSection.items,
            expanded: _expandedSections.contains('off'),
            onToggleExpanded: () => toggle('off'),
            isLoading: _loadingOff,
            itemBuilder: (_, item) => _buildGroupedRow(item, basket),
          ),
        ],
      );
    }

    // Empty search query: Habituels (max 5) + Récents only (stale-while-revalidate).
    return suggestionsAsync.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        children: const [
          SkeletonPulseBox(height: 50, borderRadius: 10),
          SizedBox(height: 8),
          SkeletonPulseBox(height: 50, borderRadius: 10),
          SizedBox(height: 8),
          SkeletonPulseBox(height: 50, borderRadius: 10),
        ],
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Impossible de charger les suggestions : $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () =>
                  ref.invalidate(foodSuggestionsProvider(basket.targetHour)),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
      data: (suggestions) {
        if (suggestions.timePicks.isEmpty && suggestions.recentFoods.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      LucideIcons.utensils,
                      size: 26,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Recherchez, scannez ou créez un aliment. Vos aliments récents et habitudes horaires apparaîtront automatiquement ici.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final hourLabel =
            '${basket.targetHour.toString().padLeft(2, '0')}:00';
        return ListView(
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            if (suggestions.timePicks.isNotEmpty) ...[
              _SectionTitle('Habituels • $hourLabel'),
              ..._buildSuggestionRows(
                suggestions.timePicks.take(5).toList(),
                basket,
              ),
              const SizedBox(height: 14),
            ],
            if (suggestions.recentFoods.isNotEmpty) ...[
              const _SectionTitle('Récents'),
              ..._buildSuggestionRows(suggestions.recentFoods, basket),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _buildSuggestionRows(
    List<FoodSuggestionItemModel> items,
    FoodBasketState basket,
  ) {
    final widgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (i > 0) widgets.add(kCompactFoodDivider);
      final count = item.isQuickAdd
          ? basket.countFor(quickName: item.name)
          : (item.isRecipe
              ? basket.countFor(recipeId: item.id)
              : basket.countFor(foodId: item.id));
      widgets.add(
        FoodSearchResultRow(
          name: item.name,
          brand: item.brand,
          stores: item.stores,
          source: item.source,
          category: item.category,
          quantityG: item.lastQuantityG,
          customQuantityText: item.isQuickAdd
              ? 'Ajout libre'
              : (item.isRecipe && item.servingWeightG != null
                  ? formatRecipeUnitSubtitle(
                      item.lastQuantityG, item.servingWeightG)
                  : null),
          kcal: item.previewKcal,
          proteinG: item.previewProteinG,
          fatG: item.previewFatG,
          carbsG: item.previewCarbsG,
          basketCount: count,
          onQuickAdd: () {
            HapticFeedback.lightImpact();
            ref.read(foodBasketProvider.notifier).addSuggestion(item);
          },
          onTapRow: () async {
            if (item.isQuickAdd) {
              setState(() {
                _quickNameController.text = item.name;
                _quickKcalController.text =
                    item.previewKcal.toStringAsFixed(item.previewKcal % 1 == 0 ? 0 : 1);
                _quickProteinController.text =
                    item.previewProteinG.toStringAsFixed(item.previewProteinG % 1 == 0 ? 0 : 1);
                _quickFatController.text =
                    item.previewFatG.toStringAsFixed(item.previewFatG % 1 == 0 ? 0 : 1);
                _quickCarbsController.text =
                    item.previewCarbsG.toStringAsFixed(item.previewCarbsG % 1 == 0 ? 0 : 1);
                _tabIndex = 2;
              });
            } else if (item.isRecipe) {
              final detail =
                  await ref.read(recipeRepositoryProvider).getRecipe(item.id);
              if (!mounted) return;
              await _openQuantitySheet(
                recipe: RecipeSummaryModel(
                  id: detail.id,
                  name: detail.name,
                  description: detail.description,
                  totalWeightG: detail.totalWeightG,
                  servingsCount: detail.servingsCount,
                  kcalPer100g: detail.kcalPer100g,
                  proteinPer100g: detail.proteinPer100g,
                  fatPer100g: detail.fatPer100g,
                  carbsPer100g: detail.carbsPer100g,
                  isShared: detail.isShared,
                ),
                initialQuantityG: item.lastQuantityG,
              );
            } else {
              await _openQuantitySheet(
                food: item.toFoodModel(),
                initialQuantityG: item.lastQuantityG,
              );
            }
          },
        ),
      );
    }
    return widgets;
  }

  Widget _buildRecipesTab(
    AsyncValue<List<RecipeSummaryModel>> recipesAsync,
    FoodBasketState basket,
  ) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecipeEditorScreen()),
              );
              ref.invalidate(recipesListProvider);
            },
            icon: const Icon(LucideIcons.chefHat, size: 16),
            label: const Text('Nouvelle recette'),
          ),
        ),
        Expanded(
          child: recipesAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.calories),
            ),
            error: (e, _) => Center(child: Text('Erreur : $e')),
            data: (recipes) {
              if (recipes.isEmpty) {
                return const Center(
                  child: Text(
                    'Aucune recette partagée pour le moment.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return ListView.separated(
                itemCount: recipes.length,
                separatorBuilder: (_, __) => kCompactFoodDivider,
                itemBuilder: (context, index) {
                  final recipe = recipes[index];
                  final defaultQty = recipe.resolvedServingWeightG ?? 100.0;
                  final factor = defaultQty / 100.0;
                  final count = basket.countFor(recipeId: recipe.id);
                  return FoodSearchResultRow(
                    name: recipe.name,
                    brand: null,
                    stores: null,
                    source: 'recipe',
                    quantityG: defaultQty,
                    customQuantityText: recipe.hasServings
                        ? formatRecipeUnitSubtitle(
                            defaultQty, recipe.resolvedServingWeightG)
                        : null,
                    kcal: recipe.kcalPer100g * factor,
                    proteinG: recipe.proteinPer100g * factor,
                    fatG: recipe.fatPer100g * factor,
                    carbsG: recipe.carbsPer100g * factor,
                    basketCount: count,
                    trailingExtra: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(LucideIcons.pencil, size: 15),
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                RecipeEditorScreen(existingRecipeId: recipe.id),
                          ),
                        );
                        ref.invalidate(recipesListProvider);
                      },
                    ),
                    onQuickAdd: () {
                      HapticFeedback.lightImpact();
                      ref.read(foodBasketProvider.notifier).addRecipe(
                            recipe,
                            quantityG: defaultQty,
                          );
                    },
                    onTapRow: () => _openQuantitySheet(
                      recipe: recipe,
                      initialQuantityG: defaultQty,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAddTab() {
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      children: [
        TextField(
          controller: _quickNameController,
          decoration: const InputDecoration(
            labelText: 'Nom (ex. Repas restaurant)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _quickKcalController,
          focusNode: _quickKcalFocusNode,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Calories (kcal)',
            labelStyle: const TextStyle(color: AppColors.calories),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.calories, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _quickProteinController,
                focusNode: _quickProteinFocusNode,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Protéines (g)',
                  labelStyle: const TextStyle(color: AppColors.protein),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.protein, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _quickFatController,
                focusNode: _quickFatFocusNode,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Lipides (g)',
                  labelStyle: const TextStyle(color: AppColors.fat),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.fat, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _quickCarbsController,
                focusNode: _quickCarbsFocusNode,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Glucides (g)',
                  labelStyle: const TextStyle(color: AppColors.carbs),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.carbs, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _submittingQuick
                    ? null
                    : () => _submitQuickAddToBasket(logAlone: true),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(LucideIcons.zap, size: 16),
                label: const Text('Logger seul'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _submittingQuick
                    ? null
                    : () => _submitQuickAddToBasket(logAlone: false),
                icon: const Icon(LucideIcons.plus, size: 18),
                label: const Text('Ajouter au panier'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderPillButton extends StatelessWidget {
  const _HeaderPillButton({
    required this.child,
    required this.onTap,
    this.highlighted = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: highlighted ? AppColors.calories : AppColors.border,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _BasketDrawer extends StatelessWidget {
  const _BasketDrawer({
    required this.basket,
    required this.onEditItem,
    required this.onRemoveItem,
    required this.onClear,
  });

  final FoodBasketState basket;
  final ValueChanged<BasketItem> onEditItem;
  final ValueChanged<String> onRemoveItem;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${basket.totalKcal.round()} kcal',
                      style: AppTheme.numericStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.calories,
                      ),
                    ),
                    Text(
                      '${basket.totalProteinG.round()} P',
                      style: AppTheme.numericStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.protein,
                      ),
                    ),
                    Text(
                      '${basket.totalFatG.round()} L',
                      style: AppTheme.numericStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.fat,
                      ),
                    ),
                    Text(
                      '${basket.totalCarbsG.round()} G',
                      style: AppTheme.numericStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.carbs,
                      ),
                    ),
                  ],
                ),
              ),
              if (basket.items.isNotEmpty)
                TextButton(
                  onPressed: onClear,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.error,
                  ),
                  child: const Text('Vider', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const Divider(height: 12),
          if (basket.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Votre panier est vide. Appuyez sur + pour ajouter des aliments.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: basket.items.length,
                separatorBuilder: (_, __) => const Divider(height: 10),
                itemBuilder: (_, idx) {
                  final item = basket.items[idx];
                  final qtyStr = item.isQuickAdd
                      ? 'Ajout libre'
                      : (item.itemType == 'recipe' &&
                              item.recipeServingWeightG != null
                          ? formatRecipeUnitSubtitle(
                              item.quantityG, item.recipeServingWeightG)
                          : (item.quantityG % 1 == 0
                              ? '${item.quantityG.round()} g'
                              : '${item.quantityG.toStringAsFixed(1)} g'));
                  return Dismissible(
                    key: ValueKey(item.localId),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => onRemoveItem(item.localId),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        LucideIcons.trash2,
                        size: 16,
                        color: AppColors.error,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => onEditItem(item),
                      child: Row(
                        children: [
                          FoodCategoryAvatar(
                            name: item.name,
                            source: item.source ??
                                (item.itemType == 'recipe' ? 'recipe' : null),
                            category: item.category,
                            size: 34,
                            borderRadius: 9,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '$qtyStr · ${item.kcal.round()} kcal',
                                  style: AppTheme.numericStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => onRemoveItem(item.localId),
                            icon: const Icon(
                              LucideIcons.trash2,
                              size: 15,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

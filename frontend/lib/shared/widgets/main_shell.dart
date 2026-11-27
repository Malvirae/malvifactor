import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/router/app_router.dart';
import 'package:malvifactor/core/services/ota_update_service.dart';
import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/providers/analytics_provider.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/food_logger/presentation/food_logger_sheet.dart';
import 'package:malvifactor/features/journal/presentation/journal_screen.dart';
import 'package:malvifactor/features/profile/providers/profile_provider.dart';
import 'package:malvifactor/features/strategy/presentation/strategy_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _otaChecked = false;

  @override
  void initState() {
    super.initState();
    if (OtaUpdateService.isSupported && !_otaChecked) {
      _otaChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          OtaUpdateService.checkAndPrompt(context);
        }
      });
    }
  }

  void _onSelectTab(int index) {
    if (index == 0) {
      ref.invalidate(dashboardProvider);
      ref.invalidate(fullMetricContextProvider);
    } else if (index == 1) {
      ref.invalidate(journalDayProvider);
    } else if (index == 2) {
      ref.invalidate(strategyProvider);
    } else if (index == 3) {
      ref.read(profileProvider.notifier).load(silent: true);
    }

    final isSameTab = index == widget.navigationShell.currentIndex;
    widget.navigationShell.goBranch(
      index,
      initialLocation: isSameTab,
    );
    if (isSameTab) {
      branchNavigatorKeys[index].currentState?.popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;
    final activeJournalDate = ref.watch(journalDateProvider);

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (currentIndex == 0 || currentIndex == 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: InkWell(
                    onTap: () => openFoodLoggerSheet(
                      context,
                      targetDate: activeJournalDate,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.search,
                            size: 17,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Rechercher un aliment...',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            tooltip: 'Scanner un code-barres',
                            onPressed: () => openFoodLoggerSheet(
                              context,
                              targetDate: activeJournalDate,
                              openScannerDirectly: true,
                            ),
                            icon: const Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 19,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              SizedBox(
                height: 60,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavItem(
                      icon: LucideIcons.layoutGrid,
                      label: 'Tableau',
                      selected: currentIndex == 0,
                      onTap: () => _onSelectTab(0),
                    ),
                    _NavItem(
                      icon: LucideIcons.apple,
                      label: 'Journal',
                      selected: currentIndex == 1,
                      onTap: () => _onSelectTab(1),
                    ),
                    GestureDetector(
                      onTap: () => openFoodLoggerSheet(
                        context,
                        targetDate: activeJournalDate,
                      ),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: AppColors.textPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.plus,
                          color: AppColors.background,
                          size: 24,
                        ),
                      ),
                    ),
                    _NavItem(
                      icon: LucideIcons.trendingUp,
                      label: 'Stratégie',
                      selected: currentIndex == 2,
                      onTap: () => _onSelectTab(2),
                    ),
                    _NavItem(
                      icon: LucideIcons.moreHorizontal,
                      label: 'Plus',
                      selected: currentIndex == 3,
                      onTap: () => _onSelectTab(3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.textPrimary : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

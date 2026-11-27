import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/auth/presentation/login_screen.dart';
import 'package:malvifactor/features/auth/providers/auth_provider.dart';
import 'package:malvifactor/features/dashboard/presentation/dashboard_screen.dart';
import 'package:malvifactor/features/journal/presentation/journal_screen.dart';
import 'package:malvifactor/features/more/presentation/more_screen.dart';
import 'package:malvifactor/features/onboarding/presentation/onboarding_screen.dart';
import 'package:malvifactor/features/profile/data/profile_repository.dart';
import 'package:malvifactor/features/profile/providers/profile_provider.dart';
import 'package:malvifactor/features/strategy/presentation/strategy_screen.dart';
import 'package:malvifactor/shared/widgets/main_shell.dart';
import 'package:malvifactor/shared/widgets/malvifactor_logo.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
    ref.listen<AsyncValue<UserProfileModel>>(
      profileProvider,
      (_, __) => notifyListeners(),
    );
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final location = state.matchedLocation;

      if (authState.status == AuthStatus.unknown) {
        return location == '/splash' ? null : '/splash';
      }

      if (authState.status == AuthStatus.unauthenticated) {
        return location == '/login' ? null : '/login';
      }

      if (authState.status == AuthStatus.authenticated) {
        final profileState = ref.read(profileProvider);
        if (profileState.isLoading && !profileState.hasValue) {
          return location == '/splash' ? null : '/splash';
        }
        final profile = profileState.valueOrNull;
        if (profile != null &&
            (!profile.onboardingCompleted || profile.initialTdeeKcal <= 0)) {
          return location == '/onboarding' ? null : '/onboarding';
        }
        if (location == '/login' || location == '/splash') {
          return '/dashboard';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/journal',
                builder: (context, state) => const JournalScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/strategy',
                builder: (context, state) => const StrategyScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/more',
                builder: (context, state) => const MoreScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MalviFactorLogo(
                size: 88,
                progress: Curves.easeOutCubic.transform(_controller.value),
              ),
              const SizedBox(height: 18),
              Opacity(
                opacity: _controller.value,
                child: const MalviFactorWordmark(fontSize: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

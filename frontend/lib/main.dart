import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/session/session_store.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_repository.dart';
import 'features/meals/meal_controller.dart';
import 'features/meals/meal_repository.dart';
import 'features/onboarding/onboarding_flow_screen.dart';
import 'features/plans/plans_controller.dart';
import 'features/plans/plans_repository.dart';
import 'features/progress/analytics_controller.dart';
import 'features/progress/analytics_repository.dart';
import 'features/progress/progress_controller.dart';
import 'features/progress/progress_repository.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/settings_repository.dart';
import 'features/splits/splits_controller.dart';
import 'features/splits/splits_repository.dart';
import 'features/today/today_controller.dart';
import 'features/today/today_repository.dart';
import 'root_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SilenApp());
}

/// Wires the whole dependency graph once, at the root, so every feature
/// reads its repository/controller through Provider instead of
/// constructing its own copy - the "shared methods, no duplicates" rule
/// applied to the app's plumbing.
class SilenApp extends StatelessWidget {
  const SilenApp({super.key});

  @override
  Widget build(BuildContext context) {
    final sessionStore = SessionStore();
    final apiClient = ApiClient(sessionStore: sessionStore);

    return MultiProvider(
      providers: [
        Provider.value(value: sessionStore),
        Provider.value(value: apiClient),
        Provider(create: (_) => AuthRepository(apiClient)),
        Provider(create: (_) => TodayRepository(apiClient)),
        Provider(create: (_) => SplitsRepository(apiClient)),
        Provider(create: (_) => ProgressRepository(apiClient)),
        Provider(create: (_) => AnalyticsRepository(apiClient)),
        Provider(create: (_) => PlansRepository(apiClient)),
        Provider(create: (_) => SettingsRepository(apiClient)),
        Provider(create: (_) => MealRepository(apiClient)),
        ChangeNotifierProvider(
            create: (ctx) =>
                AuthController(ctx.read<AuthRepository>(), sessionStore)
                  ..bootstrap()),
        ChangeNotifierProvider(
            create: (ctx) => TodayController(ctx.read<TodayRepository>())),
        ChangeNotifierProvider(
            create: (ctx) => SplitsController(ctx.read<SplitsRepository>())),
        ChangeNotifierProvider(
            create: (ctx) =>
                ProgressController(ctx.read<ProgressRepository>())),
        ChangeNotifierProvider(
            create: (ctx) =>
                AnalyticsController(ctx.read<AnalyticsRepository>())),
        ChangeNotifierProvider(
            create: (ctx) => PlansController(ctx.read<PlansRepository>())),
        ChangeNotifierProvider(
            create: (ctx) => SettingsController(
                ctx.read<SettingsRepository>(), sessionStore)),
        ChangeNotifierProvider(
            create: (ctx) => MealController(ctx.read<MealRepository>())),
      ],
      child: Consumer<SettingsController>(
        builder: (context, settingsController, _) {
          // Prefer the live/loaded appearance mode; while it's still
          // resolving, fall back to the synchronously-cached last-known
          // value so there's no flash of the wrong theme on cold start.
          final mode = settingsController.state.data?.appearanceMode ??
              sessionStore.cachedAppearanceMode;
          final themeMode = switch (mode) {
            'Light' => ThemeMode.light,
            'Dark' => ThemeMode.dark,
            // 'Device' (and null, on a genuinely first-ever launch) follow
            // the OS setting.
            _ => ThemeMode.system,
          };
          return MaterialApp(
            title: 'SilaFit',
            debugShowCheckedModeBanner: false,
            theme: buildSilenTheme(Brightness.light),
            darkTheme: buildSilenTheme(Brightness.dark),
            themeMode: themeMode,
            builder: (context, child) {
              final brightness = Theme.of(context).brightness;
              AppColors.setBrightness(brightness);
              final palette = AppColors.paletteFor(brightness);
              // Every screen reads `AppColors`'s static getters directly
              // instead of `Theme.of(context)`, so a plain `notifyListeners`
              // from flipping the appearance mode only rebuilds whichever
              // widgets happen to be listening for some other reason -
              // everything else keeps painting the brightness it was built
              // with. Keying this wrapper by the resolved brightness forces
              // Flutter to tear down and rebuild the whole app below here
              // whenever it changes, so every `AppColors` read - in Settings
              // and everywhere else - picks up the new palette immediately.
              //
              // The OS status bar / Android nav bar are drawn by the
              // platform, not by anything in this widget tree, so neither
              // the `KeyedSubtree` remount above nor any `AppColors` read
              // touches them - without this `AnnotatedRegion` they keep
              // whatever style they had at cold start forever, which reads
              // as "that one bit of small text never changes with the rest
              // of the theme" (a screen with its own `AppBar`, e.g. Splits,
              // overrides this with its own nested region while it's on
              // screen, which is the correct/expected layering).
              final overlayStyle = brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlayStyle.copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: palette.background,
                  systemNavigationBarDividerColor: palette.background,
                ),
                child: KeyedSubtree(key: ValueKey(brightness), child: child!),
              );
            },
            home: const _AppRoot(),
          );
        },
      ),
    );
  }
}

/// Blocks on the device-id bootstrap login before showing the app shell -
/// per the spec this happens silently and instantly in practice. Once
/// bootstrapped, first-launch devices see the onboarding flow instead of
/// `RootShell` until it marks itself complete (finish, skip, or log in
/// mid-flow all count) and replaces itself with `RootShell` directly.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool _settingsLoadTriggered = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        if (auth.isBootstrapping) {
          return const _SplashScreen();
        }
        // Settings needs a live device/user token, which only exists once
        // `AuthController.bootstrap()` resolves - kick it here, once, rather
        // than chaining it inside the provider's own `create`.
        if (!_settingsLoadTriggered) {
          _settingsLoadTriggered = true;
          final settingsController = context.read<SettingsController>();
          Future.microtask(settingsController.load);
        }
        final sessionStore = context.read<SessionStore>();
        if (!sessionStore.hasCompletedOnboarding) {
          return const OnboardingFlowScreen();
        }
        return const RootShell();
      },
    );
  }
}

/// Mirrors the native splash screen (see `flutter_native_splash` config in
/// `pubspec.yaml`) on first frame, then keeps the same mark on-screen with
/// a looping "Kinetic Pulse" animation - rings expanding out from the mark
/// plus a bouncing dot trio in place of a generic spinner - for however
/// long the bootstrap login actually takes.
class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) => Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    _PulseRing(t: _pulse.value, phase: 0),
                    _PulseRing(t: _pulse.value, phase: 0.5),
                    child!,
                  ],
                ),
                child: Image.asset('assets/branding/app_icon_transparent.png',
                    width: 120, height: 120),
              ),
            ),
            const SizedBox(height: 28),
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => _LoadingDots(t: _pulse.value),
            ),
          ],
        ),
      ),
    );
  }
}

/// One ring of the pulse - expands out from the mark and fades as it goes,
/// looping on the parent controller's 0-1 [t] offset by [phase] so two
/// rings launch half a cycle apart instead of in lockstep.
class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.t, required this.phase});

  final double t;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final local = (t + phase) % 1.0;
    final eased = Curves.easeOut.transform(local);
    return Opacity(
      opacity: (1 - eased) * 0.5,
      child: Container(
        width: 120 + eased * 90,
        height: 120 + eased * 90,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }
}

/// Three dots bouncing in sequence, standing in for a generic
/// [CircularProgressIndicator] with something more on-brand.
class _LoadingDots extends StatelessWidget {
  const _LoadingDots({required this.t});

  final double t;

  static double _bounce(double phase) {
    final triangle = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return Curves.easeInOut.transform(triangle);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final bounce = _bounce((t + i * 0.2) % 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Opacity(
            opacity: 0.35 + bounce * 0.65,
            child: Transform.scale(
              scale: 0.6 + bounce * 0.4,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/platform/screen_security.dart';
import 'core/session/session_store.dart';
import 'core/sync/sync_queue.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/runner_draw_splash.dart';
import 'features/account/account_repository.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_repository.dart';
import 'features/diet_guides/diet_guide_controller.dart';
import 'features/diet_guides/diet_guide_repository.dart';
import 'features/diet_plans/diet_plan_controller.dart';
import 'features/diet_plans/diet_plan_repository.dart';
import 'features/documents/trainer_documents_repository.dart';
import 'features/exercises/exercises_repository.dart';
import 'features/meals/meal_controller.dart';
import 'features/meals/meal_repository.dart';
import 'features/notifications/notifications_repository.dart';
import 'features/notifications/push_messaging_service.dart';
import 'features/onboarding/onboarding_flow_screen.dart';
import 'features/onboarding/onboarding_repository.dart';
import 'features/plans/iap_service.dart';
import 'features/plans/plans_controller.dart';
import 'features/plans/plans_repository.dart';
import 'features/progress/analytics_controller.dart';
import 'features/progress/analytics_repository.dart';
import 'features/progress/exercise_progress_controller.dart';
import 'features/progress/progress_controller.dart';
import 'features/progress/weekly_analytics_controller.dart';
import 'features/progress/progress_repository.dart';
import 'features/providers/supplement_providers_repository.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/settings_repository.dart';
import 'features/splits/splits_controller.dart';
import 'features/splits/splits_repository.dart';
import 'features/today/active_workout_draft_store.dart';
import 'features/today/exercise_memory_store.dart';
import 'features/today/today_controller.dart';
import 'features/today/today_repository.dart';
import 'root_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SilenApp());
  // No screenshots or screen recordings anywhere in the app.
  WidgetsBinding.instance
      .addPostFrameCallback((_) => ScreenSecurity.lockApp());
}

/// Wires the whole dependency graph once, at the root, so every feature
/// reads its repository/controller through Provider instead of
/// constructing its own copy - the "shared methods, no duplicates" rule
/// applied to the app's plumbing.
class SilenApp extends StatefulWidget {
  const SilenApp({super.key});

  @override
  State<SilenApp> createState() => _SilenAppState();
}

class _SilenAppState extends State<SilenApp> {
  // Owned here, above the reload key, so a reload never tears down the device
  // identity, the HTTP client, or the FCM token-refresh subscription - only
  // the per-run controllers and screens below are rebuilt.
  final _sessionStore = SessionStore();
  late final _apiClient = ApiClient(sessionStore: _sessionStore);
  late final _notificationsRepository = NotificationsRepository(_apiClient);
  // Writes made with no signal wait here until the server answers again.
  // Above the reload key so a queued workout survives a run rebuild.
  late final _syncQueue = SyncQueue(_apiClient)..start();
  // App-scoped so the FCM token-refresh subscription lives as long as the
  // app does; every registration path goes through this one instance.
  late final _pushMessagingService =
      PushMessagingService(_notificationsRepository);

  // Also above the reload key, so a snackbar queued right before a reload
  // (e.g. "Your account has been deleted.") is carried into the fresh tree.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  // One key per "app run". Bumping it rebuilds every provider, controller, and
  // screen below from scratch - a genuine cold-start reload rather than a
  // partial reset that leaves stale state behind.
  Key _runKey = UniqueKey();

  /// Wired as `AuthController`'s reload hook, so this is what sign-out and
  /// account deletion run. It discards the SharedPreferences-backed per-user
  /// caches - which, unlike the provider graph, outlive the key bump - before
  /// rebuilding the run, so neither the incoming guest nor a later account
  /// ever sees the outgoing user's in-progress workout or remembered weights.
  Future<void> _reload() async {
    await _clearLocalUserCache();
    if (!mounted) return;
    setState(() => _runKey = UniqueKey());
  }

  /// Best-effort: a storage hiccup must never stop the reload that actually
  /// signs the user out.
  Future<void> _clearLocalUserCache() async {
    try {
      await ActiveWorkoutDraftStore.instance.clear();
    } catch (_) {}
    try {
      await ExerciseMemoryStore.instance.clear();
    } catch (_) {}
    await _apiClient.clearCache();
    await _syncQueue.clear();
  }

  @override
  void dispose() {
    _syncQueue.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AppRun(
      key: _runKey,
      sessionStore: _sessionStore,
      apiClient: _apiClient,
      syncQueue: _syncQueue,
      notificationsRepository: _notificationsRepository,
      pushMessagingService: _pushMessagingService,
      messengerKey: _messengerKey,
      onReload: _reload,
    );
  }
}

/// The dependency graph for one app run. Rebuilt wholesale when the root bumps
/// its key, which is what makes sign-out/account deletion a real reload rather
/// than just a navigation change.
class _AppRun extends StatelessWidget {
  const _AppRun({
    super.key,
    required this.sessionStore,
    required this.apiClient,
    required this.syncQueue,
    required this.notificationsRepository,
    required this.pushMessagingService,
    required this.messengerKey,
    required this.onReload,
  });

  final SessionStore sessionStore;
  final ApiClient apiClient;
  final SyncQueue syncQueue;
  final NotificationsRepository notificationsRepository;
  final PushMessagingService pushMessagingService;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: sessionStore),
        Provider.value(value: apiClient),
        Provider.value(value: syncQueue),
        Provider(create: (_) => AuthRepository(apiClient)),
        Provider(create: (_) => TodayRepository(apiClient)),
        Provider(create: (_) => SplitsRepository(apiClient)),
        Provider(create: (_) => ExercisesRepository(apiClient)),
        Provider(create: (_) => DietPlanRepository(apiClient)),
        Provider(create: (_) => DietGuideRepository(apiClient)),
        Provider(create: (_) => ProgressRepository(apiClient)),
        Provider(create: (_) => AnalyticsRepository(apiClient)),
        Provider(create: (_) => PlansRepository(apiClient)),
        Provider(create: (_) => IapService()),
        Provider(create: (_) => SettingsRepository(apiClient)),
        Provider(create: (_) => MealRepository(apiClient)),
        Provider(create: (_) => TrainerDocumentsRepository(apiClient)),
        Provider(create: (_) => SupplementProvidersRepository(apiClient)),
        Provider.value(value: notificationsRepository),
        Provider.value(value: pushMessagingService),
        Provider(create: (_) => AccountRepository(apiClient)),
        ChangeNotifierProvider(
            create: (ctx) => AuthController(
                  ctx.read<AuthRepository>(),
                  sessionStore,
                  onReload: onReload,
                )..bootstrap()),
        ChangeNotifierProvider(
            create: (ctx) => TodayController(ctx.read<TodayRepository>(),
                syncQueue: syncQueue)),
        ChangeNotifierProvider(
            create: (ctx) => SplitsController(ctx.read<SplitsRepository>())),
        ChangeNotifierProvider(
            create: (ctx) => MySplitsController(ctx.read<SplitsRepository>())),
        ChangeNotifierProvider(
            create: (ctx) => DietPlansController(ctx.read<DietPlanRepository>())),
        ChangeNotifierProvider(
            create: (ctx) =>
                MyDietPlansController(ctx.read<DietPlanRepository>())),
        ChangeNotifierProvider(
            create: (ctx) =>
                ActiveDietPlanController(ctx.read<DietPlanRepository>())),
        ChangeNotifierProvider(
            create: (ctx) =>
                DietGuidesController(ctx.read<DietGuideRepository>())),
        ChangeNotifierProvider(
            create: (ctx) =>
                ProgressController(ctx.read<ProgressRepository>())),
        ChangeNotifierProvider(
            create: (ctx) =>
                ExerciseProgressController(ctx.read<ProgressRepository>())),
        ChangeNotifierProvider(
            create: (ctx) =>
                AnalyticsController(ctx.read<AnalyticsRepository>())),
        ChangeNotifierProvider(
            create: (ctx) =>
                WeeklyAnalyticsController(ctx.read<AnalyticsRepository>())),
        ChangeNotifierProvider(
            create: (ctx) => PlansController(
                ctx.read<PlansRepository>(), ctx.read<IapService>())),
        ChangeNotifierProvider(
            create: (ctx) => SettingsController(
                ctx.read<SettingsRepository>(), sessionStore)),
        ChangeNotifierProvider(
            create: (ctx) => MealController(ctx.read<MealRepository>(),
                syncQueue: syncQueue)),
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
            scaffoldMessengerKey: messengerKey,
            theme: buildSilenTheme(Brightness.light),
            darkTheme: buildSilenTheme(Brightness.dark),
            themeMode: themeMode,
            builder: (context, child) {
              final brightness = Theme.of(context).brightness;
              AppColors.setBrightness(brightness);
              ScreenSecurity.setDarkAppearance(
                  brightness == Brightness.dark);
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
  bool _pushSyncTriggered = false;

  /// Whether the runner mark has finished drawing. The splash stays up until
  /// it has, even when bootstrap resolves sooner, so it never cuts off
  /// mid-stroke. Static because a brightness flip remounts this whole subtree
  /// (see the `KeyedSubtree` in `SilenApp`), and sign-out/account-deletion
  /// rebuild `_AppRoot` too - neither should replay the cold-start splash.
  static bool _splashFinished = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        if (auth.isBootstrapping || !_splashFinished) {
          return RunnerDrawSplash(
            onFinished: () => setState(() => _splashFinished = true),
          );
        }
        // Settings needs a live device/user token, which only exists once
        // `AuthController.bootstrap()` resolves - kick it here, once, rather
        // than chaining it inside the provider's own `create`.
        if (!_settingsLoadTriggered) {
          _settingsLoadTriggered = true;
          final settingsController = context.read<SettingsController>();
          Future.microtask(settingsController.load);
          // Refreshes the cached profile gender the split artwork keys off.
          OnboardingRepository(context.read<ApiClient>())
              .getProfile()
              .then((_) {}, onError: (_) {});
        }
        final sessionStore = context.read<SessionStore>();
        if (!sessionStore.hasCompletedOnboarding) {
          return const OnboardingFlowScreen();
        }
        // Returning device: re-store the FCM token once the session exists, so
        // a token that rotated while the app was closed is not left stale.
        if (!_pushSyncTriggered) {
          _pushSyncTriggered = true;
          Future.microtask(context.read<PushMessagingService>().syncToken);
        }
        return RootShell(
          showFeatureTour: !sessionStore.hasCompletedFeatureTour,
        );
      },
    );
  }
}

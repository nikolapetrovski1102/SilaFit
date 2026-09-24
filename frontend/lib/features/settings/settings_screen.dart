import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/session/session_store.dart';
import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/legal_links.dart';
import '../../core/widgets/bottom_nav_bar.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import '../../root_shell.dart';
import '../account/account_repository.dart';
import '../auth/auth_controller.dart';
import '../notifications/push_messaging_service.dart';
import '../onboarding/onboarding_flow_screen.dart';
import '../onboarding/onboarding_models.dart';
import '../onboarding/onboarding_repository.dart';
import '../plans/plans_controller.dart';
import '../plans/plans_models.dart';
import '../plans/plans_repository.dart';
import '../plans/plans_screen.dart';
import '../plans/restore_purchases_action.dart';
import 'ai_consent_gate.dart';
import 'settings_controller.dart';
import 'settings_models.dart';

/// The Settings screen - preferences, units, and account. Originally matched
/// `settings_preferences/screen.png` (profile row, appearance toggle, unit
/// toggles, rest timer sound, barbell standard picker, workout reminders,
/// static wearable-connection chips, subscription upsell, account links);
/// the wearable-connection chips were dropped since no real HealthKit/Google
/// Fit integration backs them - subscription state and every other row here
/// reflect real session/settings data instead.
class SettingsScreen extends StatefulWidget {
  final GlobalKey? spotlightKey;

  const SettingsScreen({super.key, this.spotlightKey});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsController _controller;

  // Onboarding-collected gender/age/height/etc. isn't part of `settings` (a
  // separate `api/profile` row) - fetched once here rather than per-rebuild
  // so it survives every settings toggle's notifyListeners() without
  // re-hitting the network. Non-fatal on failure: the avatar just falls
  // back to the neutral silhouette and the details sheet shows "Not set".
  UserProfile? _profile;

  // The caller's plan from `/plans/current` - null while loading or after a
  // failed check, so the card never claims "Free" for a paying user it just
  // couldn't reach. Re-fetched whenever the session changes or a purchase /
  // restore anywhere in the app bumps [PlansController.purchaseRevision].
  CurrentSubscription? _subscription;
  bool _subscriptionFailed = false;
  Object? _session;
  int? _purchaseRevision;
  int _subscriptionRequest = 0;

  @override
  void initState() {
    super.initState();
    _controller = context.read<SettingsController>();
    if (!_controller.state.hasData) {
      Future.microtask(_controller.load);
    }
    OnboardingRepository(context.read<ApiClient>())
        .getProfile()
        .then((profile) {
      if (mounted) setState(() => _profile = profile);
    }).catchError((_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<AuthController>().session;
    final revision = context.watch<PlansController>().purchaseRevision;
    if (_session != session || _purchaseRevision != revision) {
      _session = session;
      _purchaseRevision = revision;
      _loadSubscription();
    }
  }

  Future<void> _loadSubscription() async {
    final request = ++_subscriptionRequest;
    final plans = context.read<PlansRepository>();
    setState(() {
      _subscription = null;
      _subscriptionFailed = false;
    });
    CurrentSubscription? subscription;
    try {
      subscription = await plans.getCurrent();
    } catch (_) {}
    if (!mounted || request != _subscriptionRequest) return;
    setState(() {
      _subscription = subscription;
      _subscriptionFailed = subscription == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SingleChildScrollView(
          // Bottom padding clears the floating nav pill (RootShell's
          // Scaffold extends its body under it) plus the usual breathing
          // room, so the last row scrolls up past the pill instead of
          // staying hidden beneath it.
          padding: EdgeInsets.fromLTRB(
              AppSpacing.marginMobile,
              AppSpacing.lg,
              AppSpacing.marginMobile,
              AppSpacing.sm + SilenBottomNavBar.reservedHeight(context)),
          child: _SettingsContent(
            controller: _controller,
            spotlightKey: widget.spotlightKey,
            profile: _profile,
            subscription: _subscription,
            subscriptionFailed: _subscriptionFailed,
            onReloadSubscription: _loadSubscription,
          ),
        );
      },
    );
  }
}

class _SettingsContent extends StatelessWidget {
  final SettingsController controller;
  final GlobalKey? spotlightKey;
  final UserProfile? profile;
  final CurrentSubscription? subscription;
  final bool subscriptionFailed;
  final Future<void> Function() onReloadSubscription;

  const _SettingsContent({
    required this.controller,
    this.spotlightKey,
    this.profile,
    this.subscription,
    required this.subscriptionFailed,
    required this.onReloadSubscription,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final session = auth.session;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionEyebrow('Preferences & Profile'),
        const SizedBox(height: 4),
        Text('Settings', style: AppTypography.headlineLg),
        const SizedBox(height: AppSpacing.lg),
        // The profile row only needs auth/session state, not `settings` -
        // it (and everything below it that's equally independent of
        // `settings`) stays visible even while that fetch is slow or
        // failed. Only the three preference sections below, which read
        // straight off `settings`, sit behind the ResourceBuilder.
        _ProfileRow(
          name: session?.displayName ?? session?.email ?? 'Guest Athlete',
          subtitle: auth.isRegistered
              ? (session?.email ?? 'Registered account')
              : 'Guest device - progress not linked',
          tierLabel: !auth.isRegistered
              ? 'Guest'
              : (subscription?.isPaid ?? false)
                  ? subscription!.planName
                  : 'Member',
          profile: profile,
          controller: controller,
        ),
        const SizedBox(height: AppSpacing.lg),
        ResourceBuilder<UserSettings>(
          state: controller.state,
          onRetry: controller.load,
          builder: (context, settings) => _PreferencesSections(
            controller: controller,
            settings: settings,
            spotlightKey: spotlightKey,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionEyebrow('Subscription & Data'),
        const SizedBox(height: AppSpacing.sm),
        _SubscriptionCard(
          isRegistered: auth.isRegistered,
          subscription: subscription,
          failed: subscriptionFailed,
          onReload: onReloadSubscription,
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          child: Column(
            children: [
              _LinkRow(
                  label: 'Export my data', onTap: () => _exportData(context)),
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              _LinkRow(
                  label: 'Restore purchases',
                  onTap: () => runRestorePurchases(context)),
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              _LinkRow(
                  label: 'Manage subscription',
                  onTap: () => manageSubscription(context, subscription)),
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              _LinkRow(
                  label: 'Privacy policy',
                  onTap: () =>
                      openHostedPage(context, privacyUrl, 'Privacy Policy')),
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              _LinkRow(
                  label: 'Terms of use',
                  onTap: () =>
                      openHostedPage(context, termsUrl, 'Terms of Use')),
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              _LinkRow(
                  label: 'Support',
                  onTap: () => openHostedPage(context, supportUrl, 'Support')),
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              _LinkRow(
                  label: 'Delete account',
                  labelColor: AppColors.error,
                  onTap: () => _confirmDeleteAccount(context)),
            ],
          ),
        ),
        // Keep development-only controls isolated from profile/release builds.
        // Analytics previews deliberately live on the Progress screen so even
        // debug builds exercise the authenticated production-data path.
        if (kDebugMode) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionEyebrow('Developer'),
          const SizedBox(height: AppSpacing.sm),
          SectionCard(
            child: Column(
              children: [
                _DevActionRow(
                  icon: Icons.restart_alt_rounded,
                  label: 'Start Onboarding Process',
                  subtitle:
                      'Replay full profile setup + feature tour + protocol offer',
                  onTap: () => _restartFullOnboarding(context),
                ),
                Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
                _DevActionRow(
                  icon: Icons.tour_outlined,
                  label: 'Start App Feature Tour',
                  subtitle: 'Walk through pages & Choose Your Protocol screen',
                  onTap: () => _startFeatureTourOnly(context),
                ),
                Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
                const _OnboardingDebugToggle(),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        SecondaryPillButton(
          label: 'Log Out',
          foregroundColor: AppColors.error,
          onPressed: () => _confirmLogOut(context),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Future<void> _restartFullOnboarding(BuildContext context) async {
    final sessionStore = context.read<SessionStore>();
    await sessionStore.resetAllOnboarding();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const OnboardingFlowScreen(),
      ),
      (route) => false,
    );
  }

  Future<void> _startFeatureTourOnly(BuildContext context) async {
    final sessionStore = context.read<SessionStore>();
    await sessionStore.setFeatureTourComplete(false);
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const RootShell(showFeatureTour: true),
      ),
      (route) => false,
    );
  }

  Future<void> _confirmLogOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Log Out', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _logOut(context);
  }

  /// Detaches this device from push delivery before the session goes away, so
  /// a later reminder isn't addressed to a token that no longer belongs to a
  /// signed-in user. Best-effort - logout must never block on it.
  Future<void> _logOut(BuildContext context) async {
    final pushMessaging = context.read<PushMessagingService>();
    final authController = context.read<AuthController>();
    // Must run before the session is cleared (the call needs the auth token),
    // but bounded so a stalled Firebase call can never stop the user signing
    // out. `deactivate` already swallows its own errors.
    await pushMessaging
        .deactivate()
        .timeout(const Duration(seconds: 3), onTimeout: () {});
    await authController.logout();
  }

  /// Asks the server to email the full "download my data" payload to the
  /// account's address - there's no in-app viewer for it, this is a one-shot
  /// request, not a screen.
  Future<void> _exportData(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Preparing your data export...')));
    try {
      final repository = context.read<AccountRepository>();
      final email = await repository.exportData();
      messenger.showSnackBar(
          SnackBar(content: Text('Your data export is on its way to $email.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content:
              Text('Could not prepare your data export. Please try again.')));
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        // The store owns renewal, so deleting the account can't stop billing -
        // App Review expects users to be told how to cancel (5.1.1(v)).
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'This permanently deletes your account and all of your data - '
                'profile, workouts, nutrition logs, and bodyweight history. '
                'This cannot be undone.'),
            const SizedBox(height: AppSpacing.sm),
            Text(
                'Deleting your account does not cancel an active subscription. '
                'Cancel it in your $storeName subscription settings first, or '
                'you will keep being billed.'),
            TextButton(
              onPressed: openManageSubscriptions,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text('Manage subscription'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final authController = context.read<AuthController>();
    final pushMessaging = context.read<PushMessagingService>();
    try {
      await context.read<AccountRepository>().deleteAccount();
      await pushMessaging.deactivate();
      // Queue the confirmation *before* logging out, because logout reloads
      // the whole app. The app-level messenger outlives that reload, so the
      // snackbar still lands on the fresh home screen.
      messenger.showSnackBar(
          const SnackBar(content: Text('Your account has been deleted.')));
      // Server-side data is already gone; `logout()` does the local cleanup
      // and reloads the app from a cold start, so the user sees the full
      // loading screen and then lands on Today as a brand-new guest device.
      await authController.logout();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not delete your account. Please try again.')));
    }
  }
}

/// The three preference sections that actually read off [UserSettings] -
/// split out of `_SettingsContent` so they're the only part of the screen
/// gated behind the settings fetch.
class _PreferencesSections extends StatelessWidget {
  final SettingsController controller;
  final UserSettings settings;
  final GlobalKey? spotlightKey;

  const _PreferencesSections({
    required this.controller,
    required this.settings,
    this.spotlightKey,
  });

  @override
  Widget build(BuildContext context) {
    final primaryPreferences = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionEyebrow('Appearance'),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          child: _AppearanceRow(
            mode: settings.appearanceMode,
            onSelected: controller.setAppearanceMode,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionEyebrow('Units'),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          child: Column(
            children: [
              _InlineToggleRow(
                label: 'Weight',
                options: const ['kg', 'lb'],
                selected: settings.weightUnit,
                onChanged: controller.setWeightUnit,
              ),
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              _InlineToggleRow(
                label: 'Distance',
                options: const ['km', 'mi'],
                selected: settings.distanceUnit,
                onChanged: controller.setDistanceUnit,
              ),
            ],
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (spotlightKey != null)
          KeyedSubtree(key: spotlightKey!, child: primaryPreferences)
        else
          primaryPreferences,
        const SizedBox(height: AppSpacing.lg),
        const SectionEyebrow('Training & Notifications'),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          child: Column(
            children: [
              _SwitchRow(
                label: 'Rest timer sound',
                value: settings.restTimerSoundEnabled,
                onChanged: controller.setRestTimerSoundEnabled,
              ),
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              _BarbellStandardRow(
                valueKg: settings.barbellStandardKg,
                onSelected: controller.setBarbellStandardKg,
              ),
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              _SwitchRow(
                label: 'Workout reminders',
                value: settings.notificationsEnabled,
                onChanged: controller.setNotificationsEnabled,
              ),
              if (settings.notificationsEnabled) ...[
                Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
                _ReminderTimeRow(
                  localTime: settings.notificationLocalTime,
                  onSelected: controller.setNotificationLocalTime,
                ),
              ],
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              // Turning it on goes through the same disclosure sheet the AI
              // features show, so consent is always given with the facts.
              _SwitchRow(
                label: 'Share data with AI provider',
                value: settings.aiDataConsent,
                onChanged: (value) => value
                    ? AiConsentGate.ensure(context)
                    : controller.setAiDataConsent(false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Each gender's picker order: the plain silhouette first, then its 9
/// illustrated character avatars (see frontend/assets/avatars/male|female/).
/// A profile can only ever pick from its own gender's set - see
/// [_avatarChoicesFor] - so nothing here mixes the two lists.
const kMaleAvatarChoices = [
  'Male',
  'Male1',
  'Male2',
  'Male3',
  'Male4',
  'Male5',
  'Male6',
  'Male7',
  'Male8',
  'Male9',
];
const kFemaleAvatarChoices = [
  'Female',
  'Female1',
  'Female2',
  'Female3',
  'Female4',
  'Female5',
  'Female6',
  'Female7',
  'Female8',
  'Female9',
];

/// The avatar picker's gender gate: a 'Female' profile only ever sees the
/// female set, everyone else (including 'Other' and guests who haven't set
/// a gender) sees the male set, per product decision - there's no mixed or
/// neutral illustrated set to fall back to.
List<String> _avatarChoicesFor(String? gender) =>
    gender == 'Female' ? kFemaleAvatarChoices : kMaleAvatarChoices;

/// The avatar's set picture for a given choice (a value from
/// [kMaleAvatarChoices]/[kFemaleAvatarChoices]) or an onboarding-collected
/// gender used as the fallback before a settings-level choice has loaded;
/// unset or 'Other' falls back to the plain (unornamented) male one as the
/// neutral default.
String _avatarAssetFor(String? choice) {
  if (choice == 'Female') return 'assets/branding/profile_avatar_female.svg';
  if (choice != null && choice.startsWith('Female') && choice.length > 6) {
    return 'assets/avatars/female/female_${choice.substring(6)}.png';
  }
  if (choice != null && choice.startsWith('Male') && choice.length > 4) {
    return 'assets/avatars/male/male_${choice.substring(4)}.png';
  }
  return 'assets/branding/profile_avatar_male.svg';
}

/// Renders a choice's circular avatar image - the two plain silhouettes are
/// vector (`SvgPicture`), the 18 illustrated characters are raster PNGs
/// (`Image`), so this picks the right widget from the resolved asset path's
/// extension rather than duplicating that branch at each call site.
Widget _avatarImage(String? choice, {required double size}) {
  final asset = _avatarAssetFor(choice);
  return ClipOval(
    child: asset.endsWith('.svg')
        ? SvgPicture.asset(asset, width: size, height: size, fit: BoxFit.cover)
        : Image.asset(asset, width: size, height: size, fit: BoxFit.cover),
  );
}

/// The "Subscription & Data" headline card, mapped from the caller's real
/// plan: guests get the sign-up pitch, Free users the upgrade pitch, and
/// paying users their tier, billing cycle and renewal/end date.
class _SubscriptionCard extends StatelessWidget {
  final bool isRegistered;
  final CurrentSubscription? subscription;
  final bool failed;
  final Future<void> Function() onReload;

  const _SubscriptionCard({
    required this.isRegistered,
    required this.subscription,
    required this.failed,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    final sub = subscription;
    final String title;
    final String subtitle;
    final String action;
    VoidCallback onPressed = () => _openPlans(context);

    if (!isRegistered) {
      title = 'Guest access';
      subtitle =
          'Create an account to unlock plans, AI insights, and forecasts';
      action = 'Get Started';
    } else if (sub == null) {
      title = 'SilaFit';
      subtitle = failed
          ? 'Could not check your subscription'
          : 'Checking your subscription...';
      action = failed ? 'Retry' : 'View plans';
      if (failed) onPressed = onReload;
    } else if (!sub.isPaid) {
      title = 'SilaFit Free';
      subtitle = 'Upgrade for AI insights and predictive forecasts';
      action = 'Upgrade';
    } else {
      title = 'SilaFit ${sub.planName}';
      subtitle = _paidSubtitle(sub);
      // ADVANCED is the top tier - nothing left to upsell, so the button
      // goes to the store's own subscription management instead.
      if (sub.planCode == 'ADVANCED') {
        action = 'Manage';
        onPressed = () => manageSubscription(context, sub);
      } else {
        action = 'Upgrade';
      }
    }

    return SectionCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.headlineSm),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 120,
            child: SecondaryPillButton(
              label: action,
              foregroundColor: AppColors.accent,
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    );
  }

  static String _paidSubtitle(CurrentSubscription sub) {
    final cycle = switch (sub.billingCycle) {
      'Yearly' => 'Yearly plan',
      'Monthly' => 'Monthly plan',
      _ => 'Active plan',
    };
    final expiry = sub.expiresAtUtc;
    if (expiry == null) return cycle;
    final date = DateFormat.yMMMd().format(expiry.toLocal());
    return sub.autoRenewing ? '$cycle · Renews $date' : '$cycle · Ends $date';
  }

  Future<void> _openPlans(BuildContext context) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlansScreen()));
    // A purchase bumps purchaseRevision (which reloads this on its own), but
    // a lapsed/changed plan the store reported meanwhile only shows on a refetch.
    await onReload();
  }
}

class _ProfileRow extends StatelessWidget {
  final String name;
  final String subtitle;
  final String tierLabel;
  final UserProfile? profile;
  final SettingsController controller;

  const _ProfileRow(
      {required this.name,
      required this.subtitle,
      required this.tierLabel,
      required this.controller,
      this.profile});

  @override
  Widget build(BuildContext context) {
    // The user's manual override (once settings have loaded) wins over the
    // onboarding-collected gender, which stays the fallback for guests and
    // for the moment before settings finish loading.
    final avatarChoice = controller.state.data?.avatarChoice ?? profile?.gender;
    final canPickAvatar = controller.state.hasData;
    return SectionCard(
      child: Row(
        children: [
          GestureDetector(
            onTap: canPickAvatar ? () => _openAvatarPicker(context) : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _avatarImage(avatarChoice, size: 52),
                if (canPickAvatar)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.surfaceContainer, width: 1.5),
                      ),
                      child: Icon(Icons.edit_rounded,
                          size: 10, color: AppColors.onAccent),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: GestureDetector(
              onTap: () => _openUserDetailsSheet(context, name, profile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            style: AppTypography.headlineSm,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded,
                          color: AppColors.onSurfaceVariant, size: 18),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          PillChip(label: tierLabel),
        ],
      ),
    );
  }

  /// Lets the user override which avatar shows, independent of the
  /// onboarding-collected gender it otherwise falls back to. The offered
  /// choices are still gated by that same gender - see [_avatarChoicesFor] -
  /// so a male profile can't end up on a female avatar or vice versa.
  void _openAvatarPicker(BuildContext context) {
    final current = controller.state.data?.avatarChoice;
    final choices = _avatarChoicesFor(profile?.gender);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
              AppSpacing.marginMobile, AppSpacing.marginMobile, AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Choose avatar', style: AppTypography.headlineSm),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final choice in choices)
                    GestureDetector(
                      onTap: () {
                        controller.setAvatarChoice(choice);
                        Navigator.of(sheetContext).pop();
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _avatarImage(choice, size: 56),
                          if (choice == current)
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppColors.surfaceContainer,
                                      width: 1.5),
                                ),
                                child: Icon(Icons.check_rounded,
                                    size: 12, color: AppColors.onAccent),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One labeled row in the user-details sheet - blank/null answers show as
/// 'Not set' rather than being omitted, so the sheet's shape doesn't shift
/// based on how much of onboarding was completed.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ),
          Text(value, style: AppTypography.bodyMd),
        ],
      ),
    );
  }
}

const _goalLabels = {
  'BuildMuscle': 'Build muscle',
  'LoseFat': 'Lose fat',
  'MaintainActive': 'Maintain & stay active',
};

const _experienceLabels = {
  'Beginner': 'Beginner',
  'Intermediate': 'Intermediate',
  'Advanced': 'Advanced',
};

const _equipmentLabels = {
  'FullGym': 'Full gym',
  'Dumbbells': 'Dumbbells',
  'Bodyweight': 'Bodyweight only',
};

String _detailOr(String? value, [Map<String, String>? labels]) {
  if (value == null) return 'Not set';
  return labels?[value] ?? value;
}

/// Opens the onboarding-answers sheet from a tap on the profile row's
/// username - the same details `CompleteProfileFlow` collects, shown
/// read-only here since editing them happens through onboarding, not
/// Settings.
void _openUserDetailsSheet(
    BuildContext context, String name, UserProfile? profile) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
            AppSpacing.marginMobile, AppSpacing.marginMobile, AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: AppTypography.headlineSm),
            const SizedBox(height: AppSpacing.sm),
            _DetailRow(label: 'Gender', value: _detailOr(profile?.gender)),
            _DetailRow(
                label: 'Age',
                value: profile?.ageYears != null
                    ? '${profile!.ageYears} yrs'
                    : 'Not set'),
            _DetailRow(
                label: 'Height',
                value: profile?.heightCm != null
                    ? '${profile!.heightCm!.round()} cm'
                    : 'Not set'),
            _DetailRow(
                label: 'Weight',
                value: profile?.weightKg != null
                    ? '${profile!.weightKg!.round()} kg'
                    : 'Not set'),
            _DetailRow(
                label: 'Goal', value: _detailOr(profile?.goal, _goalLabels)),
            _DetailRow(
                label: 'Training experience',
                value:
                    _detailOr(profile?.trainingExperience, _experienceLabels)),
            _DetailRow(
                label: 'Equipment access',
                value: _detailOr(profile?.equipmentAccess, _equipmentLabels)),
            _DetailRow(
                label: 'Training days/week',
                value: profile?.trainingDaysPerWeek?.toString() ?? 'Not set'),
            _DetailRow(
                label: 'Session length',
                value: profile?.sessionDurationMinutes != null
                    ? '${profile!.sessionDurationMinutes} min'
                    : 'Not set'),
            _DetailRow(
                label: 'Daily activity level',
                value: _detailOr(profile?.dailyActivityLevel)),
          ],
        ),
      ),
    ),
  );
}

/// One choice in the Appearance picker - value is what's sent to
/// [SettingsController.setAppearanceMode] ('Dark' / 'Light' / 'Device'),
/// label/icon are what the row and the modal show for it.
class _AppearanceModeOption {
  final String value;
  final String label;
  final IconData icon;

  const _AppearanceModeOption(
      {required this.value, required this.label, required this.icon});
}

const _appearanceModeOptions = [
  _AppearanceModeOption(
      value: 'Light', label: 'Light', icon: Icons.light_mode_rounded),
  _AppearanceModeOption(
      value: 'Dark', label: 'Dark', icon: Icons.dark_mode_rounded),
  _AppearanceModeOption(
      value: 'Device', label: 'Match device', icon: Icons.smartphone_rounded),
];

/// The Appearance settings row - shows the active mode's icon/label and
/// opens [_AppearanceModeSheet] on tap, rather than exposing all three
/// choices inline. Falls back to the 'Device' option's icon for any value
/// that doesn't match a known mode (only reachable if a future server value
/// is added before the client knows about it).
class _AppearanceRow extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onSelected;

  const _AppearanceRow({required this.mode, required this.onSelected});

  _AppearanceModeOption get _current => _appearanceModeOptions.firstWhere(
        (option) => option.value == mode,
        orElse: () => _appearanceModeOptions.last,
      );

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return GestureDetector(
      onTap: () => _openSheet(context),
      child: Row(
        children: [
          Icon(current.icon, color: AppColors.onSurfaceVariant, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('Appearance', style: AppTypography.bodyMd)),
          Text(current.label,
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant, size: 20),
        ],
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
              AppSpacing.marginMobile, AppSpacing.marginMobile, AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Appearance', style: AppTypography.headlineSm),
              const SizedBox(height: AppSpacing.sm),
              for (final option in _appearanceModeOptions)
                _AppearanceOptionTile(
                  option: option,
                  selected: option.value == mode,
                  onTap: () {
                    onSelected(option.value);
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of [_AppearanceRow]'s modal - an icon badge (filled once
/// selected), the mode's label, and a trailing check on the active one.
class _AppearanceOptionTile extends StatelessWidget {
  final _AppearanceModeOption option;
  final bool selected;
  final VoidCallback onTap;

  const _AppearanceOptionTile(
      {required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.inset),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryContainer.withOpacity(0.4) : null,
          borderRadius: BorderRadius.circular(AppRadius.inset),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.accent
                    : AppColors.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(option.icon,
                  size: 20,
                  color: selected
                      ? AppColors.onAccent
                      : AppColors.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(option.label, style: AppTypography.bodyMd)),
            if (selected)
              Icon(Icons.check_circle_rounded, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}

/// A label on the left, a compact two-option pill toggle on the right - used
/// for the unit rows (Weight kg/lb, Distance km/mi).
class _InlineToggleRow extends StatelessWidget {
  final String label;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  const _InlineToggleRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.bodyMd)),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                GestureDetector(
                  onTap: () => onChanged(option),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: option == selected ? AppColors.accent : null,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      option,
                      style: AppTypography.labelSm.copyWith(
                          color: option == selected
                              ? AppColors.onAccent
                              : AppColors.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.bodyMd)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.onAccent,
          activeTrackColor: AppColors.accent,
          inactiveTrackColor: AppColors.surfaceContainerHigh,
        ),
      ],
    );
  }
}

class _BarbellStandardRow extends StatelessWidget {
  final double valueKg;
  final ValueChanged<double> onSelected;

  const _BarbellStandardRow({required this.valueKg, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openPicker(context),
      child: Row(
        children: [
          Expanded(
              child: Text('Barbell standard', style: AppTypography.bodyMd)),
          Text('${valueKg.toStringAsFixed(0)} kg',
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant, size: 20),
        ],
      ),
    );
  }

  void _openPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.marginMobile),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Barbell standard', style: AppTypography.headlineSm),
              const SizedBox(height: AppSpacing.sm),
              for (final option in kBarbellStandardOptionsKg)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${option.toStringAsFixed(0)} kg',
                      style: AppTypography.bodyMd),
                  trailing: option == valueKg
                      ? Icon(Icons.check_circle_rounded,
                          color: AppColors.accent)
                      : null,
                  onTap: () {
                    onSelected(option);
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reminder-time row under "Workout reminders" - parses the
/// `HH:mm:ss` wire format into a [TimeOfDay] for display/picking and
/// serializes back the same way on selection.
class _ReminderTimeRow extends StatelessWidget {
  final String localTime;
  final ValueChanged<String> onSelected;

  const _ReminderTimeRow({required this.localTime, required this.onSelected});

  TimeOfDay get _time {
    final parts = localTime.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
    return TimeOfDay(hour: hour ?? 8, minute: minute ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _pickTime(context),
      child: Row(
        children: [
          Expanded(child: Text('Reminder time', style: AppTypography.bodyMd)),
          Text(_time.format(context),
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant, size: 20),
        ],
      ),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    onSelected('$hh:$mm:00');
  }
}

/// Debug-build-only switch that flips [SessionStore.hasCompletedOnboarding]
/// so the first-launch onboarding flow can be replayed without reinstalling
/// the app or clearing device storage by hand. Never shown in release
/// builds - gated by `kDebugMode` at the call site.
///
/// Turning it off immediately drops into [OnboardingFlowScreen]; turning it
/// back on just marks onboarding complete again without navigating, since
/// the dev is presumably still inside that replayed flow or back in
/// Settings already.
class _OnboardingDebugToggle extends StatefulWidget {
  const _OnboardingDebugToggle();

  @override
  State<_OnboardingDebugToggle> createState() => _OnboardingDebugToggleState();
}

class _OnboardingDebugToggleState extends State<_OnboardingDebugToggle> {
  @override
  Widget build(BuildContext context) {
    final sessionStore = context.read<SessionStore>();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Onboarding completed', style: AppTypography.bodyMd),
              const SizedBox(height: 2),
              Text('Off replays the first-launch flow',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
        Switch(
          value: sessionStore.hasCompletedOnboarding,
          onChanged: (value) => _toggle(context, sessionStore, value),
          activeThumbColor: AppColors.onAccent,
          activeTrackColor: AppColors.accent,
          inactiveTrackColor: AppColors.surfaceContainerHigh,
        ),
      ],
    );
  }

  Future<void> _toggle(
      BuildContext context, SessionStore sessionStore, bool value) async {
    if (!value) {
      await sessionStore.resetAllOnboarding();
    } else {
      await sessionStore.setOnboardingComplete(true);
    }
    if (!context.mounted) return;
    setState(() {});
    if (!value) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const OnboardingFlowScreen(),
        ),
        (route) => false,
      );
    }
  }
}

class _DevActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _DevActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.inset),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.inset),
              ),
              child: Icon(icon, size: 20, color: AppColors.accent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.bodyMd),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? labelColor;

  const _LinkRow({required this.label, required this.onTap, this.labelColor});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: AppTypography.bodyMd.copyWith(color: labelColor))),
          Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant, size: 20),
        ],
      ),
    );
  }
}

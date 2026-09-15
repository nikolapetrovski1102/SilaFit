import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/session/session_store.dart';
import '../../core/dev_flags.dart';
import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/bottom_nav_bar.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import '../account/account_repository.dart';
import '../auth/auth_controller.dart';
import '../notifications/push_messaging_service.dart';
import '../onboarding/onboarding_flow_screen.dart';
import '../plans/plans_screen.dart';
import '../progress/monthly_overview_mock.dart';
import '../progress/monthly_overview_screen.dart';
import '../progress/weekly_overview_mock.dart';
import 'settings_controller.dart';
import 'settings_models.dart';

/// Support and Privacy Policy are real hosted pages, not in-app content.
const _supportUrl = 'https://sila.fitness/support.html';
const _privacyUrl = 'https://sila.fitness/privacy.html';

/// The Settings screen - preferences, units, and account. Originally matched
/// `settings_preferences/screen.png` (profile row, appearance toggle, unit
/// toggles, rest timer sound, barbell standard picker, workout reminders,
/// static wearable-connection chips, subscription upsell, account links);
/// the wearable-connection chips were dropped since no real HealthKit/Google
/// Fit integration backs them - subscription state and every other row here
/// reflect real session/settings data instead.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<SettingsController>();
    if (!_controller.state.hasData) {
      Future.microtask(_controller.load);
    }
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
          child: _SettingsContent(controller: _controller),
        );
      },
    );
  }
}

class _SettingsContent extends StatelessWidget {
  final SettingsController controller;

  const _SettingsContent({required this.controller});

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
          tierLabel: auth.isRegistered ? 'Member' : 'Guest',
        ),
        const SizedBox(height: AppSpacing.lg),
        ResourceBuilder<UserSettings>(
          state: controller.state,
          onRetry: controller.load,
          builder: (context, settings) => _PreferencesSections(
              controller: controller, settings: settings),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionEyebrow('Subscription & Data'),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(auth.isRegistered ? 'SilaFit Free' : 'Guest access',
                        style: AppTypography.headlineSm),
                    const SizedBox(height: 2),
                    Text(
                        auth.isRegistered
                            ? 'Upgrade for AI insights and predictive forecasts'
                            : 'Create an account to unlock plans, AI insights, and forecasts',
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 120,
                child: SecondaryPillButton(
                  label: auth.isRegistered ? 'Upgrade' : 'Get Started',
                  foregroundColor: AppColors.accent,
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PlansScreen())),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          child: Column(
            children: [
              _LinkRow(
                  label: 'Export my data',
                  onTap: () => _exportData(context)),
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              _LinkRow(
                  label: 'Privacy policy',
                  onTap: () => _openUrl(context, _privacyUrl)),
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              _LinkRow(
                  label: 'Support', onTap: () => _openUrl(context, _supportUrl)),
              Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
              _LinkRow(
                  label: 'Delete account',
                  labelColor: AppColors.error,
                  onTap: () => _confirmDeleteAccount(context)),
            ],
          ),
        ),
        // TEMPORARY: `kDevToolsInRelease` (core/dev_flags.dart) keeps this
        // section visible in release builds too. Normally debug builds only.
        if (kDebugMode || kDevToolsInRelease) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionEyebrow('Developer'),
          const SizedBox(height: AppSpacing.sm),
          SectionCard(
            child: Column(
              children: [
                const _OnboardingDebugToggle(),
                Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
                _LinkRow(
                  label: 'Simulate monthly overview',
                  onTap: () => _simulateMonthlyOverview(context),
                ),
                Divider(height: AppSpacing.lg, color: AppColors.outlineVariant),
                _LinkRow(
                  label: 'Simulate weekly overview (Advanced)',
                  onTap: () => _simulateWeeklyOverview(context),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        SecondaryPillButton(
          label: 'Log Out',
          foregroundColor: AppColors.error,
          onPressed: () => _logOut(context),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  /// Detaches this device from push delivery before the session goes away, so
  /// a later reminder isn't addressed to a token that no longer belongs to a
  /// signed-in user. Best-effort - logout must never block on it.
  Future<void> _logOut(BuildContext context) async {
    final pushMessaging = context.read<PushMessagingService>();
    final authController = context.read<AuthController>();
    await pushMessaging.deactivate();
    await authController.logout();
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url.')));
    }
  }

  /// Fetches the full "download my data" payload and hands it to the native
  /// share sheet as a JSON file - there's no in-app viewer for it, this is a
  /// one-shot export, not a screen.
  Future<void> _exportData(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Preparing your data export...')));
    try {
      final repository = context.read<AccountRepository>();
      final data = await repository.exportData();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(RegExp('[:.]'), '-');
      final file = File('${dir.path}/silafit-data-export-$timestamp.json');
      await file.writeAsString(json);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'My SilaFit data export',
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Could not prepare your data export. Please try again.')));
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
            'This permanently deletes your account and all of your data - '
            'profile, workouts, nutrition logs, bodyweight history, and '
            'subscription. This cannot be undone.'),
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
      // Server-side data is already gone; clearing the local session and
      // bootstrapping fresh reuses the exact same client-side cleanup
      // AuthController.logout() already does for a guest device.
      await authController.logout();
      messenger.showSnackBar(
          const SnackBar(content: Text('Your account has been deleted.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content:
              Text('Could not delete your account. Please try again.')));
    }
  }

  /// Dev-only preview: builds a fresh on-device mock report (see
  /// `monthly_overview_mock.dart`) and pushes the full recap flow exactly as
  /// a real user would see it, without touching the backend or requiring a
  /// month of seeded history first. Debug builds only - gated by the
  /// `kDebugMode` check around this whole Developer section.
  void _simulateMonthlyOverview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => MonthlyOverviewScreen(
          analytics: buildSimulatedMonthlyAnalytics(),
          preview: true,
          onDone: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  /// Same dev-only preview as [_simulateMonthlyOverview], but for the
  /// ADVANCED weekly recap - including the meal/split recommendation slides.
  void _simulateWeeklyOverview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => MonthlyOverviewScreen(
          analytics: buildSimulatedWeeklyAnalytics(),
          preview: true,
          onDone: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }
}

/// The three preference sections that actually read off [UserSettings] -
/// split out of `_SettingsContent` so they're the only part of the screen
/// gated behind the settings fetch.
class _PreferencesSections extends StatelessWidget {
  final SettingsController controller;
  final UserSettings settings;

  const _PreferencesSections(
      {required this.controller, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Column(
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
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String name;
  final String subtitle;
  final String tierLabel;

  const _ProfileRow(
      {required this.name, required this.subtitle, required this.tierLabel});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              // Decoded at ~3x the 52x52 display box instead of the source
              // PNG's full 1024x1024 (see app_header.dart's avatar for the
              // same fix and why it matters).
              image: DecorationImage(
                image: ResizeImage(
                  AssetImage('assets/branding/profile_avatar.png'),
                  width: 156,
                ),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTypography.headlineSm),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          PillChip(label: tierLabel),
        ],
      ),
    );
  }
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
    await sessionStore.setOnboardingComplete(value);
    if (!context.mounted) return;
    setState(() {});
    if (!value) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingFlowScreen()),
        (route) => false,
      );
    }
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

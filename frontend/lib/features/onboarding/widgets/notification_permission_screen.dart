import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/silen_button.dart';
import 'onboarding_step_transition.dart';

/// The closing screen of the flow: animated bell, "Stay on track" pitch,
/// a real OS notification-permission prompt behind "Allow notifications",
/// and a "Not now" skip - either path finishes onboarding the same way.
class NotificationPermissionScreen extends StatelessWidget {
  final VoidCallback onBack;
  final bool isSubmitting;

  /// True when the OS permission was actually granted (or the platform has no
  /// prompt to grant), false for "Not now"/denied - the caller saves the
  /// timezone + opt-in either way, just with a different enabled flag.
  final ValueChanged<bool> onFinish;

  const NotificationPermissionScreen({
    super.key,
    required this.onBack,
    required this.isSubmitting,
    required this.onFinish,
  });

  /// permission_handler only ships an implementation for Android, iOS, web,
  /// and Windows - macOS and Linux have no `notification` handler and throw
  /// MissingPluginException, so skip the request there.
  static bool get _supportsNotificationPermission =>
      kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  Future<void> _requestAndFinish() async {
    var granted = true;
    if (_supportsNotificationPermission) {
      final status = await Permission.notification.request();
      granted = status.isGranted;
    }
    onFinish(granted);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                GestureDetector(
                  onTap: onBack,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceContainerHigh),
                    child: Icon(Icons.arrow_back,
                        size: 18, color: AppColors.onSurface),
                  ),
                ),
              ],
            ),
            Expanded(
              flex: 6,
              child: OnboardingStepContentTransition(
                child: Semantics(
                  image: true,
                  label: 'Ringing notification bell',
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.96,
                      heightFactor: 0.96,
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          AppColors.accent,
                          BlendMode.srcIn,
                        ),
                        child: Lottie.asset(
                          'assets/lottie_animations/ringtone.json',
                          fit: BoxFit.contain,
                          repeat: !MediaQuery.disableAnimationsOf(context),
                          animate: !MediaQuery.disableAnimationsOf(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            OnboardingStepContentTransition(
              incomingOffset: 14,
              child: Column(
                children: [
                  Text('Stay on track',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLg),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Get a nudge on workout days and reminders when it’s time to log your progress.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
            PrimaryPillButton(
              label: 'Allow notifications',
              isLoading: isSubmitting,
              onPressed: isSubmitting ? null : _requestAndFinish,
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: GestureDetector(
                onTap: isSubmitting ? null : () => onFinish(false),
                child: Text('Not now',
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

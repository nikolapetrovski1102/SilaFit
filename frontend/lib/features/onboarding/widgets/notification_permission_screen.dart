import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/silen_button.dart';
import 'intro_slide.dart';

/// The closing screen of the flow: bell icon mark, "Stay on track" pitch,
/// a real OS notification-permission prompt behind "Allow notifications",
/// and a "Not now" skip - either path finishes onboarding the same way.
class NotificationPermissionScreen extends StatelessWidget {
  final VoidCallback onBack;
  final int progressStep;
  final int progressStepCount;
  final bool isSubmitting;
  final VoidCallback onFinish;

  const NotificationPermissionScreen({
    super.key,
    required this.onBack,
    required this.progressStep,
    required this.progressStepCount,
    required this.isSubmitting,
    required this.onFinish,
  });

  /// permission_handler only ships an implementation for Android, iOS, web,
  /// and Windows - macOS and Linux have no `notification` handler and throw
  /// MissingPluginException, so skip the request there.
  static bool get _supportsNotificationPermission =>
      kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  Future<void> _requestAndFinish() async {
    if (_supportsNotificationPermission) {
      await Permission.notification.request();
    }
    onFinish();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
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
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: LayoutBuilder(builder: (context, constraints) {
                    return Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                          width: constraints.maxWidth *
                              (progressStep / progressStepCount).clamp(0, 1),
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
            const Spacer(flex: 3),
            Center(
              child: OnboardingIconMark(
                child: Icon(Icons.notifications_outlined,
                    size: 72, color: AppColors.accent),
              ),
            ),
            const Spacer(flex: 2),
            Text('Stay on track',
                textAlign: TextAlign.center, style: AppTypography.headlineLg),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Get a nudge on workout days and reminders when it’s time to log your progress.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant, height: 1.4),
            ),
            const Spacer(flex: 3),
            PrimaryPillButton(
              label: 'Allow notifications',
              isLoading: isSubmitting,
              onPressed: isSubmitting ? null : _requestAndFinish,
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: GestureDetector(
                onTap: isSubmitting ? null : onFinish,
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

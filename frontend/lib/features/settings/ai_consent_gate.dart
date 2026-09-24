import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/legal_links.dart';
import '../../core/widgets/silen_button.dart';
import 'settings_controller.dart';

/// Asks for consent before any AI feature sends the user's data to the
/// third-party AI provider (App Review 5.1.1(i) / 5.1.2(i): name who gets the
/// data and what is sent, and get permission first). The backend enforces the
/// same rule and answers 428 without it - this is only the friendly front.
///
/// Call [AiConsentGate.ensure] right before an action that may generate an AI
/// review or plan. Returns true once consent is recorded; the choice can be
/// revoked from Settings at any time.
class AiConsentGate {
  AiConsentGate._();

  static Future<bool> ensure(BuildContext context) async {
    final settings = context.read<SettingsController>();
    if (!settings.state.hasData) await settings.load();
    // Settings couldn't load - let the request through; the server still
    // refuses without consent, and the caller shows its message.
    final current = settings.state.data;
    if (current == null) return true;
    if (current.aiDataConsent) return true;
    if (!context.mounted) return false;

    final allowed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      builder: (_) => const _AiConsentSheet(),
    );
    if (allowed != true) return false;
    return settings.setAiDataConsent(true);
  }
}

class _AiConsentSheet extends StatelessWidget {
  const _AiConsentSheet();

  @override
  Widget build(BuildContext context) {
    final body =
        AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
            AppSpacing.marginMobile, AppSpacing.marginMobile, AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.auto_awesome_rounded,
                color: AppColors.secondary, size: 32),
            const SizedBox(height: AppSpacing.sm),
            Text('Share your data with our AI provider?',
                style: AppTypography.headlineSm),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'AI reviews and AI weekly plans are written by a third-party AI '
              'service. To create them, SilaFit sends OpenRouter, and the '
              'AI model provider it routes the request to, the following:',
              style: body,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final item in const [
              'Your display name',
              'Workouts: sessions, exercises, weights, volume, effort and streaks',
              'Nutrition: logged meals, calories and your calorie and macro targets',
              'Body weight change, training goal, experience level and equipment',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: body),
                    Expanded(child: Text(item, style: body)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Your email and account details are never sent. The data is used only to '
              'generate your review or plan. You can turn this off anytime '
              'in Settings.',
              style: body,
            ),
            TextButton(
              onPressed: () =>
                  openHostedPage(context, privacyUrl, 'Privacy Policy'),
              child: const Text('Read our Privacy Policy'),
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryPillButton(
              label: 'Allow',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppSpacing.sm),
            SecondaryPillButton(
              label: "Don't allow",
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

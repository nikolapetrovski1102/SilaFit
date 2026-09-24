import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/silen_button.dart';
import 'onboarding_step_transition.dart';

/// Shared chrome for every assessment question: a soft square back button,
/// title and compact step count, then the animated question content and a
/// pinned bottom CTA.
class QuestionScaffold extends StatelessWidget {
  final VoidCallback onBack;
  final int progressStep; // 1-based
  final int progressStepCount;
  final String headline;
  final Widget body;
  final String ctaLabel;
  final VoidCallback? onCta;
  final bool ctaLoading;
  final Widget? belowCta;
  final bool hideBelowCta;
  final Widget? footer;

  /// The header title next to the back button - "Assessment" for onboarding,
  /// overridable for other step-by-step flows built on this same shell (e.g.
  /// the split creation wizard).
  final String title;

  const QuestionScaffold({
    super.key,
    required this.onBack,
    required this.progressStep,
    required this.progressStepCount,
    required this.headline,
    required this.body,
    required this.ctaLabel,
    required this.onCta,
    this.ctaLoading = false,
    this.belowCta,
    this.hideBelowCta = false,
    this.footer,
    this.title = 'Assessment',
  });

  @override
  Widget build(BuildContext context) {
    // `belowCta` (OAuth row, resend-code link, ...) is secondary to the
    // field the user is actively typing into - once the keyboard is up,
    // collapse it out of the way instead of letting it get squeezed into a
    // cramped strip right above the keys. It fades/collapses back in as
    // soon as the keyboard is dismissed. `hideBelowCta` lets a caller force
    // the same collapse straight off a field's focus state, so it doesn't
    // depend on keyboard-inset timing/propagation at all.
    final keyboardOpen =
        hideBelowCta || MediaQuery.viewInsetsOf(context).bottom > 0;

    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _BackButton(onTap: onBack),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(title,
                      style: AppTypography.headlineMd.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
                ),
                _StepCounter(step: progressStep, stepCount: progressStepCount),
              ],
            ),
            const SizedBox(height: AppSpacing.xxxl),
            Expanded(
              child: OnboardingStepContentTransition(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headline,
                        style: AppTypography.headlineLg.copyWith(
                          fontSize: 32,
                          height: 1.08,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: AppSpacing.xl),
                    Expanded(
                      child: LayoutBuilder(builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                minHeight: constraints.maxHeight),
                            child: body,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryPillButton(
                label: ctaLabel, onPressed: onCta, isLoading: ctaLoading),
            if (belowCta != null)
              ClipRect(
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  heightFactor: keyboardOpen ? 0 : 1,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: keyboardOpen ? 0 : 1,
                    child: IgnorePointer(
                      ignoring: keyboardOpen,
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: belowCta,
                      ),
                    ),
                  ),
                ),
              ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Center(child: footer),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: Material(
        color: Colors.transparent,
        child: Ink(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.48),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(17),
            child: Center(
              child: Icon(Icons.chevron_left_rounded,
                  size: 28, color: AppColors.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepCounter extends StatelessWidget {
  final int step;
  final int stepCount;
  const _StepCounter({required this.step, required this.stepCount});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step $step of $stepCount',
      child: Padding(
        key: const Key('assessment-step-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: RichText(
          text: TextSpan(
            style: AppTypography.labelCaps.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
            children: [
              TextSpan(
                text: step.toString().padLeft(2, '0'),
                style: TextStyle(color: AppColors.onSurface),
              ),
              TextSpan(
                text: '  /  ',
                style: TextStyle(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
              TextSpan(
                text: stepCount.toString().padLeft(2, '0'),
                style: TextStyle(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

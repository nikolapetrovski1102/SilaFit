import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/upgrade_lock_card.dart';
import '../../plans/plans_screen.dart';
import '../diet_plan_models.dart';
import 'diet_plan_card.dart';

/// Free-tier stand-in for the diet-plan catalog: a blurred sample of plan
/// cards behind the upgrade prompt, the same treatment `SplitsScreen` gives
/// its locked library. Shown whenever `/diet-plans` answers 403.
class LockedDietPlans extends StatelessWidget {
  /// Called after the user returns from the plans screen, so the caller can
  /// re-fetch and unlock itself if they just upgraded.
  final VoidCallback onReturn;

  const LockedDietPlans({super.key, required this.onReturn});

  static const _placeholder = [
    DietPlan(
      dietPlanId: 'locked-lean-bulk',
      name: 'Lean Bulk',
      description: 'High-protein weekly plan built around your training days.',
      periodType: 'Weekly',
      durationDays: 7,
      isSystemDefault: true,
    ),
    DietPlan(
      dietPlanId: 'locked-cut',
      name: 'Steady Cut',
      description: 'A gentle calorie deficit that keeps protein high.',
      periodType: 'Monthly',
      durationDays: 28,
      isSystemDefault: true,
    ),
    DietPlan(
      dietPlanId: 'locked-balanced',
      name: 'Balanced Everyday',
      description: 'Simple, repeatable meals for maintenance.',
      periodType: 'Weekly',
      durationDays: 7,
      isSystemDefault: true,
    ),
  ];

  Future<void> _openPlans(BuildContext context) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlansScreen()));
    onReturn();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
          child: IgnorePointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final plan in _placeholder) ...[
                  DietPlanCard(plan: plan),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: Align(
            alignment: const Alignment(0, -0.4),
            child: UpgradeLockCard(
              title: 'Diet plans made for you',
              message: 'Follow weekly and monthly meal plans matched to your '
                  'targets, or build your own. Logging meals food by food '
                  'stays free.',
              actionLabel: 'Unlock diet plans',
              onUnlock: () => _openPlans(context),
            ),
          ),
        ),
      ],
    );
  }
}

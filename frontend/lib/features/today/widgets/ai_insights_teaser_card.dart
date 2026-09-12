import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart' show AppRadius;
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/slim_action_row.dart';
import '../../plans/plans_screen.dart';

/// A static, locked-look teaser for the Pro "AI monthly overview" - no real
/// AI call backs it (consistent with the rule-based-insights precedent
/// already used on Progress), it's purely a merchandising card that routes
/// into Plans when tapped.
///
/// Kept to one slim row (gradient + border carried over from the old full
/// card so the "Pro" merchandising still reads as distinct) rather than its
/// own two-line card - it's a teaser, not something that needs to compete
/// with the day's actual session for attention.
class AiInsightsTeaserCard extends StatelessWidget {
  final double scale;

  const AiInsightsTeaserCard({super.key, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    return SlimActionRow(
      icon: Icons.auto_awesome_rounded,
      iconColor: AppColors.secondary,
      iconBackground: AppColors.secondary.withOpacity(0.16),
      label: 'MONTHLY AI OVERVIEW',
      value: 'Unlock your personalized training trend',
      scale: scale,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.secondaryContainer.withOpacity(0.18),
          AppColors.surfaceContainer,
        ],
      ),
      borderColor: AppColors.secondary.withOpacity(0.3),
      trailing: Container(
        padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
        decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(AppRadius.full)),
        child: Text('PRO',
            style: AppTypography.labelCaps
                .copyWith(color: AppColors.onAccent, fontSize: 9 * scale)),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PlansScreen()),
      ),
    );
  }
}

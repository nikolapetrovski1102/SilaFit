import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'section_eyebrow.dart';

/// One small icon+label readout on a [BestMatchCard] (e.g. "Intermediate",
/// "420 kcal", "6 days").
class BestMatchMeta {
  final IconData icon;
  final String label;

  const BestMatchMeta(this.icon, this.label);
}

/// The app's opinionated "this is the one" card - a raised, accent-tinted
/// surface that reads as a recommendation from the app rather than another
/// item in the library.
///
/// This is deliberately the only loud element above the fold on the Splits
/// and Meals screens: as those catalogs keep growing, the default view stays
/// one card plus a deliberate "browse everything" action instead of a wall of
/// content. The whole card is the tap target; [actionLabel] is the affordance
/// cue, not a separate button.
class BestMatchCard extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String reason;
  final IconData icon;
  final List<BestMatchMeta> meta;
  final String actionLabel;
  final VoidCallback onTap;

  const BestMatchCard({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.reason,
    required this.icon,
    required this.onTap,
    this.meta = const [],
    this.actionLabel = 'See details',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          // A soft accent wash rather than a flat fill: it lifts the pick off
          // the plain library cards without competing with the accent pill
          // buttons elsewhere on the screen.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.accent.withOpacity(0.22),
              AppColors.surfaceContainer,
            ],
          ),
          border: Border.all(
            color: AppColors.accent.withOpacity(0.45),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: AppColors.accent),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionEyebrow(eyebrow, color: AppColors.accent),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: AppTypography.headlineSm,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(reason,
                style:
                    AppTypography.bodySm.copyWith(color: AppColors.onSurface)),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [for (final m in meta) _MetaPill(meta: m)],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Text(actionLabel,
                    style: AppTypography.labelSm.copyWith(
                        color: AppColors.accent, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded,
                    size: 16, color: AppColors.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final BestMatchMeta meta;

  const _MetaPill({required this.meta});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 4),
          Text(meta.label,
              style: AppTypography.labelSm
                  .copyWith(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'section_card.dart';

/// The collapsed "see everything" affordance shared by the Splits and Meals
/// library screens. Deliberately styled as a control rather than content, so
/// it doesn't read as another item in the catalog it opens.
///
/// This is the counterpart to `BestMatchCard`: the pick stays above the fold,
/// the full (and growing) catalog stays one deliberate tap away.
class BrowseAllToggle extends StatelessWidget {
  final bool open;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const BrowseAllToggle({
    super.key,
    required this.open,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SectionCard(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding, vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.grid_view_rounded,
                size: 20, color: AppColors.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTypography.headlineSm.copyWith(fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.bodySm),
                ],
              ),
            ),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

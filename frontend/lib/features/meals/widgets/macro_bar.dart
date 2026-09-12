import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart' show AppRadius;
import '../../../core/theme/app_typography.dart';

/// A reusable inset-track percentage-fill bar for one macro
/// (protein/carbs/fats), animated toward its new ratio whenever consumed
/// grams change.
class MacroBar extends StatelessWidget {
  final String label;
  final int consumedG;
  final int targetG;
  final Color color;

  const MacroBar({
    super.key,
    required this.label,
    required this.consumedG,
    required this.targetG,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = targetG <= 0 ? 0.0 : (consumedG / targetG).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTypography.labelSm),
            Text('${consumedG}g / ${targetG}g',
                style: AppTypography.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: Container(
            height: 8,
            color: AppColors.surfaceContainerHighest,
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => FractionallySizedBox(
                widthFactor: value,
                child: Container(color: color),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

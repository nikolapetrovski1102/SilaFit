import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart' show AppRadius;
import '../theme/app_typography.dart';

/// The small uppercase tracked-out label used above headings everywhere
/// ("SESSION READINESS", "SYSTEM TELEMETRY & ACCESS", ...).
class SectionEyebrow extends StatelessWidget {
  final String text;
  final Color? color;

  const SectionEyebrow(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.labelCaps
          .copyWith(color: color ?? AppColors.onSurfaceVariant),
    );
  }
}

/// A rounded-pill chip, e.g. the "System Telemetry & Access" badge on Plans
/// or filter pills on Splits.
class PillChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  const PillChip(
      {super.key,
      required this.label,
      this.icon,
      this.selected = false,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.primaryContainer : AppColors.surfaceContainerHigh;
    final fg = selected ? AppColors.onPrimaryContainer : AppColors.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(AppRadius.full)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6)
              ],
              Text(label.toUpperCase(),
                  style: AppTypography.labelCaps.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

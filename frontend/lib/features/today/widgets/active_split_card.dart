import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/dumbbell_icon.dart';
import '../../../core/widgets/container_transform.dart';
import '../../../core/widgets/slim_action_row.dart';
import '../../splits/splits_screen.dart';
import '../today_controller.dart';
import '../today_models.dart';

/// Replaces the old "armed push trigger" banner on Today: surfaces the
/// user's currently active split, or a prompt to pick one if they haven't
/// activated anything yet. Tapping through opens the split library so
/// browsing/switching splits is still reachable without a dedicated tab.
///
/// Sized up from `SlimActionRow`'s default - this is the one piece of
/// Today that tells the user what program they're actually running, so it
/// reads as a real row rather than the quiet secondary line the AI
/// insights teaser next to it stays at.
class ActiveSplitCard extends StatelessWidget {
  final ActiveSplit? activeSplit;
  final double scale;
  final GlobalKey? spotlightKey;

  /// How much bigger than a standard SlimActionRow this reads, on top of
  /// the FitHeight `scale` every row on Today already carries. Modest now
  /// that the value text sizes itself dynamically (see `valueStyle` below)
  /// rather than being forced to one large fixed size.
  static const _emphasis = 1.15;

  const ActiveSplitCard({super.key, required this.activeSplit, this.scale = 1, this.spotlightKey});

  @override
  Widget build(BuildContext context) {
    final split = activeSplit;
    final value = split == null
        ? 'Tap to choose a split'
        : split.durationDays != null
            ? '${split.name} · ${split.durationDays}-day program'
            : split.name ?? 'Split active';

    final rowScale = scale * _emphasis;
    final todayController = context.read<TodayController>();
    final card = ContainerTransform(
      openBuilder: (_) => const SplitsScreen(),
      onClosed: () => unawaited(todayController.load(force: true)),
      closedBuilder: (context, openContainer) => SlimActionRow(
        icon: Icons.fitness_center_rounded,
        iconWidget:
            SoftDumbbellIcon(size: 22 * rowScale, color: AppColors.accent),
        iconColor: AppColors.accent,
        iconBackground: AppColors.accent.withOpacity(0.16),
        label: 'ACTIVE SPLIT',
        value: value,
        // A ceiling, not a fixed size - FittedBox in SlimActionRow scales
        // this down for a long split name and leaves it be for a short one,
        // so nothing sits oversized just because the row itself was scaled
        // up.
        valueStyle: AppTypography.bodyLg.copyWith(
            fontSize: 16 * rowScale,
            height: 24 / 16,
            fontWeight: FontWeight.w600),
        scale: rowScale,
        trailing: Icon(Icons.chevron_right_rounded,
            color: AppColors.onSurfaceVariant, size: 24 * rowScale),
        onTap: openContainer,
      ),
    );
    if (spotlightKey != null) {
      return KeyedSubtree(key: spotlightKey!, child: card);
    }
    return card;
  }
}

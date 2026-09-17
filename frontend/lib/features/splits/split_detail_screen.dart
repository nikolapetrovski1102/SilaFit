import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/duration_format.dart';
import '../../core/widgets/hero_container_transform.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import '../today/today_controller.dart';
import 'split_builder_screen.dart';
import 'split_recommendation.dart';
import 'splits_controller.dart';
import 'splits_models.dart';
import 'splits_repository.dart';

class SplitDetailScreen extends StatefulWidget {
  final SplitDetailController controller;
  final String splitName;

  const SplitDetailScreen(
      {super.key, required this.controller, required this.splitName});

  @override
  State<SplitDetailScreen> createState() => _SplitDetailScreenState();
}

class _SplitDetailScreenState extends State<SplitDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred - see the matching comment in today_screen.dart: load()'s
    // first notifyListeners() must not fire synchronously mid-build.
    Future.microtask(widget.controller.load);
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final ok = await widget.controller.activate();
    if (!mounted) return;
    if (ok) {
      // Home's dashboard is loaded once and cached, so without this the newly
      // activated split's session (and its exercises) would not appear until a
      // manual pull-to-refresh.
      context.read<TodayController>().load(force: true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${widget.splitName} is now your active split.')));
    } else if (widget.controller.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.actionError!)));
    }
  }

  Future<void> _keep() async {
    final ok = await widget.controller.keep();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This split is now permanently yours.')));
    } else if (widget.controller.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.actionError!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.splitName, style: AppTypography.headlineSm),
        actions: [
          if (widget.controller.state.data?.split.isEditableByMe == true)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final repository = context.read<SplitsRepository>();
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SplitBuilderScreen(
                    controller: SplitBuilderController(repository,
                        splitId: widget.controller.splitId),
                  ),
                ));
                if (!mounted) return;
                widget.controller.load(force: true);
              },
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutterMobile),
            child: ResourceBuilder<SplitDetail>(
              state: widget.controller.state,
              onRetry: widget.controller.load,
              builder: (context, detail) => _DetailBody(
                  detail: detail,
                  controller: widget.controller,
                  onActivate: _activate,
                  onKeep: _keep),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final SplitDetail detail;
  final SplitDetailController controller;
  final VoidCallback onActivate;
  final VoidCallback onKeep;

  const _DetailBody(
      {required this.detail,
      required this.controller,
      required this.onActivate,
      required this.onKeep});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Hero(
          tag: 'split-hero-${detail.split.splitId}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: detail.split.heroImageUrl != null
                  ? Image.network(detail.split.heroImageUrl!, fit: BoxFit.cover)
                  : Image.asset('assets/branding/split_hero.png',
                      fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Everything below the hero image reveals only after the card has
        // mostly finished expanding into place, instead of the whole
        // screen's content just being there the moment it's pushed. That
        // delayed fade+rise is what actually reads as the expanded card
        // "showing" the split's options, rather than a screen that happened
        // to open on top of it.
        HeroExpandReveal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionEyebrow(splitCategoryLabel(detail.split.category),
                  color: AppColors.accent),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  _MetaPill(
                      icon: Icons.calendar_view_week_rounded,
                      label: '${detail.split.durationDays} days'),
                  const SizedBox(width: AppSpacing.xs),
                  _MetaPill(
                      icon: Icons.trending_up_rounded,
                      label: detail.split.level),
                  const SizedBox(width: AppSpacing.xs),
                  _MetaPill(
                      icon: Icons.event_repeat_rounded,
                      label: '${detail.days.length} workout days'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (detail.split.description != null) ...[
                Text(detail.split.description!, style: AppTypography.bodyMd),
                const SizedBox(height: AppSpacing.md),
              ],
              PrimaryPillButton(
                label: controller.activated
                    ? 'Split Activated'
                    : 'Activate This Split',
                icon: controller.activated
                    ? Icons.check_rounded
                    : Icons.play_arrow_rounded,
                isLoading: controller.isActivating,
                onPressed: controller.activated ? null : onActivate,
              ),
              if (detail.split.isAiGenerated &&
                  detail.split.aiKeptAtUtc == null) ...[
                const SizedBox(height: AppSpacing.sm),
                SecondaryPillButton(
                  label: controller.isKeeping ? 'Keeping...' : 'Keep This Plan',
                  icon: Icons.push_pin_outlined,
                  onPressed: controller.isKeeping ? null : onKeep,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  "AI-generated for this week. Keep it and it's yours for good — "
                  'otherwise it refreshes next Sunday.',
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text('WEEKLY BREAKDOWN', style: AppTypography.labelCaps),
              const SizedBox(height: AppSpacing.sm),
              for (final day in detail.days) ...[
                _DayCard(day: day),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 4),
          Text(label,
              style: AppTypography.labelSm
                  .copyWith(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final SplitDayWithExercises day;

  const _DayCard({required this.day});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: day.day.isRestDay
                      ? AppColors.surfaceContainerHigh
                      : AppColors.accent,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${day.day.dayIndex}',
                  style: AppTypography.labelCaps.copyWith(
                      color: day.day.isRestDay
                          ? AppColors.onSurfaceVariant
                          : AppColors.onAccent),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(day.day.title,
                        style: AppTypography.headlineSm.copyWith(fontSize: 16)),
                    if (day.day.focusLabel != null)
                      Text(day.day.focusLabel!.toUpperCase(),
                          style: AppTypography.labelCaps
                              .copyWith(color: AppColors.accent)),
                  ],
                ),
              ),
              if (!day.day.isRestDay)
                Text(formatMinutesLabel(day.day.estimatedMinutes),
                    style: AppTypography.labelSm
                        .copyWith(color: AppColors.onSurfaceVariant)),
            ],
          ),
          if (day.exercises.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(color: AppColors.outlineVariant, height: 1),
            const SizedBox(height: AppSpacing.sm),
            for (final exercise in day.exercises)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(exercise.name,
                            style: AppTypography.bodySm
                                .copyWith(color: AppColors.onSurface))),
                    Text(
                      '${exercise.targetSets} x ${exercise.targetRepsLow}-${exercise.targetRepsHigh}',
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

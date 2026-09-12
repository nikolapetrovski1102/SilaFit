import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/hero_container_transform.dart';
import '../../core/widgets/mascot/mascot_empty_state.dart';
import '../../core/widgets/mascot/mascot_pose.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import 'split_detail_screen.dart';
import 'splits_controller.dart';
import 'splits_models.dart';
import 'splits_repository.dart';

class SplitsScreen extends StatefulWidget {
  const SplitsScreen({super.key});

  @override
  State<SplitsScreen> createState() => _SplitsScreenState();
}

class _SplitsScreenState extends State<SplitsScreen> {
  late final SplitsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<SplitsController>();
    // Deferred - see the matching comment in today_screen.dart: load()'s
    // first notifyListeners() must not fire synchronously mid-build.
    Future.microtask(_controller.load);
  }

  @override
  Widget build(BuildContext context) {
    // A pushed screen (this used to be a tab, which got its Scaffold/SafeArea
    // for free from RootShell) needs its own Scaffold: without a Material
    // ancestor, text falls back to WidgetsApp's default style - underlined,
    // as a debug cue - and without a SafeArea the header sits under the
    // status bar/notch.
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: _controller.load,
            color: AppColors.accent,
            backgroundColor: AppColors.surfaceContainer,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                  AppSpacing.sm, AppSpacing.marginMobile, AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Present the instant this screen is pushed, regardless of
                  // whether `_controller.load()` has resolved yet - this is
                  // the Hero that Home's "Active split" row expands into
                  // (ActiveSplitCard), and a Hero flight needs its
                  // destination widget to already exist when the push
                  // happens rather than gated behind the data fetch below.
                  const Hero(
                    tag: 'active-split-hero',
                    child: _SplitsHeader(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  HeroExpandReveal(
                    child: ResourceBuilder<List<WorkoutSplit>>(
                      state: _controller.state,
                      onRetry: _controller.load,
                      builder: (context, splits) => _SplitsList(splits: splits),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SplitsHeader extends StatelessWidget {
  const _SplitsHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionEyebrow('Training Protocols', color: AppColors.accent),
        const SizedBox(height: 4),
        Text('Workout Splits', style: AppTypography.headlineLg),
      ],
    );
  }
}

class _SplitsList extends StatefulWidget {
  final List<WorkoutSplit> splits;

  const _SplitsList({required this.splits});

  @override
  State<_SplitsList> createState() => _SplitsListState();
}

class _SplitsListState extends State<_SplitsList> {
  // null = "All Splits". Categories are derived from whatever the backend
  // actually returns rather than a hardcoded taxonomy, so a new split
  // category shows up as a working filter with no frontend change needed.
  String? _filter;
  // A separate toggle rather than a synthetic "category" - matchesGoal cuts
  // across categories (e.g. a BuildMuscle match can be PPL or Arnold split).
  bool _recommendedOnly = false;

  @override
  Widget build(BuildContext context) {
    final categories = {for (final s in widget.splits) s.category}.toList()
      ..sort();
    final hasRecommendations = widget.splits.any((s) => s.matchesGoal);
    var visible = _filter == null
        ? widget.splits
        : widget.splits.where((s) => s.category == _filter).toList();
    if (_recommendedOnly) {
      visible = visible.where((s) => s.matchesGoal).toList();
    } else {
      // Surface goal-matched splits first without hiding the rest, so the
      // library still reads as "everything" when no filter is active.
      visible = [
        ...visible.where((s) => s.matchesGoal),
        ...visible.where((s) => !s.matchesGoal),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length + 1 + (hasRecommendations ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, i) {
              if (i == 0) {
                return PillChip(
                  label: 'All Splits',
                  selected: _filter == null && !_recommendedOnly,
                  onTap: () => setState(() {
                    _filter = null;
                    _recommendedOnly = false;
                  }),
                );
              }
              if (hasRecommendations && i == 1) {
                return PillChip(
                  label: 'Recommended for you',
                  selected: _recommendedOnly,
                  onTap: () => setState(() => _recommendedOnly = !_recommendedOnly),
                );
              }
              final category = categories[i - 1 - (hasRecommendations ? 1 : 0)];
              return PillChip(
                label: category,
                selected: _filter == category,
                onTap: () => setState(() {
                  _filter = category;
                  _recommendedOnly = false;
                }),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionEyebrow('Split Library'),
            Text('${visible.length} Protocols',
                style: AppTypography.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (visible.isEmpty && widget.splits.isEmpty)
          const MascotEmptyState(
            pose: MascotPose.ready,
            title: 'No splits yet',
            message: 'Your training protocols will show up here once they\'re ready.',
          )
        else if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
                child: Text('No splits match this filter.',
                    style: AppTypography.bodySm)),
          ),
        for (final split in visible) ...[
          _SplitCard(split: split),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _SplitCard extends StatelessWidget {
  final WorkoutSplit split;

  const _SplitCard({required this.split});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<SplitsRepository>();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(heroExpandRoute(
        builder: (_) => SplitDetailScreen(
          controller: SplitDetailController(repository, split.splitId),
          splitName: split.name,
        ),
      )),
      // The whole card - not just its image - is the Hero, so the tap target
      // itself is what visibly grows into the detail screen. createRectTween
      // swaps out the Navigator's default MaterialRectArcTween (which arcs
      // the flight diagonally) for a straight tween, since a card "expanding"
      // in place should grow, not travel. crossfadeHeroShuttle then
      // crossfades this card's full content into the destination's plain
      // hero image as the rect grows, instead of Hero's default hard swap to
      // the destination child partway through the flight.
      child: Hero(
        tag: 'split-hero-${split.splitId}',
        createRectTween: straightHeroRectTween,
        flightShuttleBuilder: crossfadeHeroShuttle,
        child: SectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadius.inset)),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: split.heroImageUrl != null
                          ? Image.network(split.heroImageUrl!, fit: BoxFit.cover)
                          // No per-split hero image on record yet - the same
                          // stock training photo every split card falls back
                          // to in `workout_splits_library/code.html`.
                          : Image.asset('assets/branding/split_hero.png',
                              fit: BoxFit.cover),
                    ),
                  ),
                  if (split.isSystemDefault)
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: 4),
                        decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                  color: Colors.black, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            Text('FEATURED',
                                style: AppTypography.labelCaps
                                    .copyWith(color: AppColors.onAccent)),
                          ],
                        ),
                      ),
                    ),
                  if (split.matchesGoal)
                    Positioned(
                      top: AppSpacing.sm,
                      left: AppSpacing.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: 4),
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome_rounded,
                                size: 12, color: AppColors.accent),
                            const SizedBox(width: 6),
                            Text('FOR YOU',
                                style: AppTypography.labelCaps
                                    .copyWith(color: AppColors.accent)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionEyebrow(split.category),
                    const SizedBox(height: 6),
                    Text(split.name, style: AppTypography.headlineSm),
                    if (split.description != null) ...[
                      const SizedBox(height: 4),
                      Text(split.description!,
                          style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        _MetaPill(
                            icon: Icons.calendar_view_week_rounded,
                            label: '${split.durationDays} days'),
                        const SizedBox(width: AppSpacing.xs),
                        _MetaPill(
                            icon: Icons.trending_up_rounded,
                            label: split.level),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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

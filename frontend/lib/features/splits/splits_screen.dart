import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/best_match_card.dart';
import '../../core/widgets/browse_all_toggle.dart';
import '../../core/widgets/hero_container_transform.dart';
import '../../core/widgets/mascot/mascot_empty_state.dart';
import '../../core/widgets/mascot/mascot_pose.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import 'my_splits_screen.dart';
import 'split_detail_screen.dart';
import 'split_recommendation.dart';
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MySplitsScreen())),
            icon: Icon(Icons.edit_note_rounded, color: AppColors.onSurface),
            label: Text('My splits',
                style: AppTypography.labelSm.copyWith(color: AppColors.onSurface)),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return SingleChildScrollView(
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
                    builder: (context, splits) =>
                        _SplitsContent(splits: splits),
                  ),
                ),
              ],
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

/// The ranked landing view: the single best protocol for this user as an
/// opinionated hero, then the full library collapsed behind a deliberate
/// "browse" action. Adding more splits grows the library behind that action
/// rather than lengthening the default view.
class _SplitsContent extends StatefulWidget {
  final List<WorkoutSplit> splits;

  const _SplitsContent({required this.splits});

  @override
  State<_SplitsContent> createState() => _SplitsContentState();
}

class _SplitsContentState extends State<_SplitsContent> {
  bool _browsingAll = false;

  @override
  Widget build(BuildContext context) {
    if (widget.splits.isEmpty) {
      return const MascotEmptyState(
        pose: MascotPose.ready,
        title: 'No splits yet',
        message:
            'Your training protocols will show up here once they\'re ready.',
      );
    }

    final ranked = rankSplitMatches(widget.splits);
    final best = ranked.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BestMatchHero(match: best),
        if (ranked.length > 1) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionEyebrow('More for you'),
          const SizedBox(height: AppSpacing.sm),
          for (final match in ranked.skip(1).take(3)) ...[
            _SplitPickRow(match: match),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
        const SizedBox(height: AppSpacing.lg),
        BrowseAllToggle(
          open: _browsingAll,
          title: 'Browse all ${widget.splits.length} protocols',
          subtitle: _browsingAll
              ? 'Showing the full library'
              : 'Filter every split in the library',
          onTap: () => setState(() => _browsingAll = !_browsingAll),
        ),
        if (_browsingAll) ...[
          const SizedBox(height: AppSpacing.md),
          _SplitLibrary(splits: widget.splits),
        ],
      ],
    );
  }
}

class _BestMatchHero extends StatelessWidget {
  final SplitMatch match;

  const _BestMatchHero({required this.match});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<SplitsRepository>();
    final split = match.split;
    return BestMatchCard(
      eyebrow: split.matchesGoal ? 'Best for you' : 'Start here',
      title: split.name,
      reason: match.reason,
      icon: Icons.auto_awesome_rounded,
      meta: [
        BestMatchMeta(
            Icons.calendar_view_week_rounded, '${split.durationDays} days'),
        BestMatchMeta(Icons.trending_up_rounded, split.level),
        BestMatchMeta(
            Icons.category_rounded, splitCategoryLabel(split.category)),
      ],
      actionLabel: 'View this protocol',
      onTap: () => Navigator.of(context).push(heroExpandRoute(
        builder: (_) => SplitDetailScreen(
          controller: SplitDetailController(repository, split.splitId),
          splitName: split.name,
        ),
      )),
    );
  }
}

/// A compact row for one of the 3 runners-up below the hero - deliberately
/// lighter than [_SplitCard] (no image) so the default screen stays short no
/// matter how large the library grows.
class _SplitPickRow extends StatelessWidget {
  final SplitMatch match;

  const _SplitPickRow({required this.match});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<SplitsRepository>();
    final split = match.split;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(heroExpandRoute(
        builder: (_) => SplitDetailScreen(
          controller: SplitDetailController(repository, split.splitId),
          splitName: split.name,
        ),
      )),
      child: SectionCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionEyebrow(splitCategoryLabel(split.category)),
                  const SizedBox(height: 4),
                  Text(split.name,
                      style: AppTypography.headlineSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(match.reason,
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// The full catalog, filters included - shown only once the user opts into
/// browsing, so the default screen stays short no matter how big the library
/// gets.
class _SplitLibrary extends StatefulWidget {
  final List<WorkoutSplit> splits;

  const _SplitLibrary({required this.splits});

  @override
  State<_SplitLibrary> createState() => _SplitLibraryState();
}

class _SplitLibraryState extends State<_SplitLibrary> {
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
                  onTap: () =>
                      setState(() => _recommendedOnly = !_recommendedOnly),
                );
              }
              final category = categories[i - 1 - (hasRecommendations ? 1 : 0)];
              return PillChip(
                label: splitCategoryLabel(category),
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
        if (visible.isEmpty)
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
                          ? Image.network(split.heroImageUrl!,
                              fit: BoxFit.cover)
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
                    SectionEyebrow(splitCategoryLabel(split.category)),
                    const SizedBox(height: 6),
                    Text(split.name, style: AppTypography.headlineSm),
                    if (split.description != null) ...[
                      const SizedBox(height: 4),
                      Text(split.description!,
                          style: AppTypography.bodyMd
                              .copyWith(color: AppColors.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _MetaPill(
                            icon: Icons.calendar_view_week_rounded,
                            label: '${split.durationDays} days'),
                        _MetaPill(
                            icon: Icons.trending_up_rounded,
                            label: split.level),
                        if (split.isEditableByMe)
                          const _MetaPill(
                              icon: Icons.edit_rounded, label: 'Your split')
                        // Anything not shipped by SilaFit and not owned by
                        // this user is a trainer's own protocol, shown
                        // because it was made public or assigned to them.
                        else if (!split.isSystemDefault)
                          const _MetaPill(
                              icon: Icons.fitness_center_rounded,
                              label: 'From your coach'),
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

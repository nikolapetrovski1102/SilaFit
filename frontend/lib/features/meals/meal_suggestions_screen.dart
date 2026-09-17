import '../../core/widgets/container_transform.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/best_match_card.dart';
import '../../core/widgets/browse_all_toggle.dart';
import '../../core/widgets/mascot/mascot_empty_state.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import 'meal_controller.dart';
import 'meal_models.dart';
import 'meal_recommendation.dart';
import 'meal_suggestion_detail_screen.dart';

/// The full "Suggested Meals" library - a dedicated listing screen for
/// browsing/activating curated meal ideas, structurally mirroring
/// SplitsScreen: filter chips derived from the data, a card per item, tap
/// through to a detail screen with the actual activate action.
///
/// The Nutrition screen keeps its own capped horizontal strip for a quick
/// glance; this screen is the "see all" destination for the full catalog.
class MealSuggestionsScreen extends StatefulWidget {
  const MealSuggestionsScreen({super.key});

  @override
  State<MealSuggestionsScreen> createState() => _MealSuggestionsScreenState();
}

class _MealSuggestionsScreenState extends State<MealSuggestionsScreen> {
  late final MealController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<MealController>();
    // Deferred - see the matching comment in today_screen.dart: load()'s
    // first notifyListeners() must not fire synchronously mid-build.
    Future.microtask(() {
      // The library's "best for you" pick is ranked against the selected
      // day's remaining calories/protein, so make sure the day half is loaded
      // when this screen is opened cold. It's normally already loaded because
      // the only entry point is the Nutrition tab's "See all".
      if (_controller.state.data == null) {
        _controller.load();
      } else {
        _controller.loadSuggestions();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // A pushed screen needs its own Scaffold/SafeArea - same reasoning as
    // SplitsScreen, which this mirrors.
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                AppSpacing.sm, AppSpacing.marginMobile, AppSpacing.sm),
            child: ResourceBuilder<List<MealSuggestion>>(
              state: _controller.suggestionsState,
              onRetry: _controller.loadSuggestions,
              builder: (context, suggestions) =>
                  _SuggestionsContent(suggestions: suggestions),
            ),
          );
        },
      ),
    );
  }
}

/// The ranked landing view: one opinionated "best right now" pick, then the
/// full (growing) catalog collapsed behind a deliberate browse action.
class _SuggestionsContent extends StatefulWidget {
  final List<MealSuggestion> suggestions;

  const _SuggestionsContent({required this.suggestions});

  @override
  State<_SuggestionsContent> createState() => _SuggestionsContentState();
}

class _SuggestionsContentState extends State<_SuggestionsContent> {
  bool _browsingAll = false;

  @override
  Widget build(BuildContext context) {
    // Re-read per build: the shared MealController may have resolved the
    // selected day after this screen appeared, and the ranking below depends
    // on that day's remaining calories/protein.
    final day = context.read<MealController>().state.data;
    final ranked = rankMealMatches(widget.suggestions, day: day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionEyebrow('Curated Ideas', color: AppColors.accent),
        const SizedBox(height: 4),
        Text('Suggested Meals', style: AppTypography.headlineLg),
        const SizedBox(height: AppSpacing.md),
        if (widget.suggestions.isEmpty)
          const MascotEmptyState(
            title: 'No suggestions yet',
            message:
                'Curated meal ideas will show up here once they\'re ready.',
          )
        else ...[
          _BestMatchHero(match: ranked.first),
          if (ranked.length > 1) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionEyebrow('More for you'),
            const SizedBox(height: AppSpacing.sm),
            for (final match in ranked.skip(1).take(3)) ...[
              _SuggestionCard(
                suggestion: match.suggestion,
                reason: match.reason,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
          const SizedBox(height: AppSpacing.lg),
          BrowseAllToggle(
            open: _browsingAll,
            title: 'Browse all ${widget.suggestions.length} meals',
            subtitle: _browsingAll
                ? 'Showing the full library'
                : 'Filter every meal in the library',
            onTap: () => setState(() => _browsingAll = !_browsingAll),
          ),
          if (_browsingAll) ...[
            const SizedBox(height: AppSpacing.md),
            _MealLibrary(suggestions: widget.suggestions),
          ],
        ],
      ],
    );
  }
}

class _BestMatchHero extends StatelessWidget {
  final MealMatch match;

  const _BestMatchHero({required this.match});

  @override
  Widget build(BuildContext context) {
    final suggestion = match.suggestion;
    final meals = context.read<MealController>();
    return ContainerTransform(
      openBuilder: (_) => MealSuggestionDetailScreen(
        controller: MealSuggestionActivationController(meals, suggestion),
      ),
      closedBuilder: (context, openContainer) => BestMatchCard(
        eyebrow: 'Best for you right now',
        title: suggestion.title,
        reason: match.reason,
        icon: Icons.restaurant_rounded,
        meta: [
          BestMatchMeta(Icons.restaurant_menu_rounded, suggestion.mealType),
          BestMatchMeta(Icons.local_fire_department_rounded,
              '${suggestion.caloriesKcal} kcal'),
          BestMatchMeta(
              Icons.egg_alt_rounded, '${suggestion.proteinG}g protein'),
        ],
        actionLabel: 'View this meal',
        onTap: openContainer,
      ),
    );
  }
}

/// The full catalog, filters + incremental pagination included - the catalog
/// runs into the hundreds, so even an explicit "browse all" stays bounded
/// rather than rendering every card at once.
class _MealLibrary extends StatefulWidget {
  final List<MealSuggestion> suggestions;

  const _MealLibrary({required this.suggestions});

  @override
  State<_MealLibrary> createState() => _MealLibraryState();
}

class _MealLibraryState extends State<_MealLibrary> {
  static const _pageSize = 20;

  // null = "All Meals". Filters are derived from whatever meal types the
  // backend actually returns, same reasoning as SplitsScreen's category
  // filter - a new meal type shows up as a working filter with no frontend
  // change needed.
  String? _filter;
  int _visibleCount = _pageSize;

  void _selectFilter(String? filter) {
    setState(() {
      _filter = filter;
      // A filter change is a fresh browse - don't carry the previous page
      // depth into the new result set.
      _visibleCount = _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mealTypes = {for (final s in widget.suggestions) s.mealType}.toList()
      ..sort();
    final filtered = _filter == null
        ? widget.suggestions
        : widget.suggestions.where((s) => s.mealType == _filter).toList();
    final visibleCount =
        _visibleCount < filtered.length ? _visibleCount : filtered.length;
    final visible = filtered.take(visibleCount).toList();
    final hasMore = visibleCount < filtered.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: mealTypes.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, i) {
              if (i == 0) {
                return PillChip(
                  label: 'All Meals',
                  selected: _filter == null,
                  onTap: () => _selectFilter(null),
                );
              }
              final mealType = mealTypes[i - 1];
              return PillChip(
                label: mealType,
                selected: _filter == mealType,
                onTap: () => _selectFilter(mealType),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionEyebrow('Meal Library'),
            Text('${filtered.length} Meals',
                style: AppTypography.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
                child: Text('No meals match this filter.',
                    style: AppTypography.bodySm)),
          ),
        for (final suggestion in visible) ...[
          _SuggestionCard(suggestion: suggestion),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (hasMore) ...[
          const SizedBox(height: AppSpacing.sm),
          SecondaryPillButton(
            label: 'Show ${filtered.length - visibleCount} more',
            icon: Icons.expand_more_rounded,
            onPressed: () => setState(() => _visibleCount += _pageSize),
          ),
        ],
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final MealSuggestion suggestion;

  /// Person-fit sentence from the recommendation engine, shown only in the
  /// "More for you" shortlist - the full library stays scannable without it.
  final String? reason;

  const _SuggestionCard({required this.suggestion, this.reason});

  @override
  Widget build(BuildContext context) {
    final meals = context.read<MealController>();
    return ContainerTransform(
      openBuilder: (_) => MealSuggestionDetailScreen(
        controller: MealSuggestionActivationController(meals, suggestion),
      ),
      closedBuilder: (context, openContainer) => GestureDetector(
        onTap: openContainer,
        child: SectionCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionEyebrow(suggestion.mealType),
                    const SizedBox(height: 6),
                    Text(suggestion.title, style: AppTypography.headlineSm),
                    if (reason != null) ...[
                      const SizedBox(height: 4),
                      Text(reason!,
                          style: AppTypography.labelSm
                              .copyWith(color: AppColors.accent),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    if (suggestion.description != null) ...[
                      const SizedBox(height: 4),
                      Text(suggestion.description!,
                          style: AppTypography.bodyMd
                              .copyWith(color: AppColors.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        _MetaPill(
                            icon: Icons.local_fire_department_rounded,
                            label: '${suggestion.caloriesKcal} kcal'),
                        const SizedBox(width: AppSpacing.xs),
                        _MetaPill(
                            icon: Icons.egg_alt_rounded,
                            label: '${suggestion.proteinG}g protein'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.onSurfaceVariant),
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

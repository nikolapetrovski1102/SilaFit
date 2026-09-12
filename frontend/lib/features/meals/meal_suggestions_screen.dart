import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/mascot/mascot_empty_state.dart';
import '../../core/widgets/mascot/mascot_pose.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import 'meal_controller.dart';
import 'meal_models.dart';
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
    Future.microtask(_controller.loadSuggestions);
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
          return RefreshIndicator(
            onRefresh: _controller.loadSuggestions,
            color: AppColors.accent,
            backgroundColor: AppColors.surfaceContainer,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                  AppSpacing.sm, AppSpacing.marginMobile, AppSpacing.sm),
              child: ResourceBuilder<List<MealSuggestion>>(
                state: _controller.suggestionsState,
                onRetry: _controller.loadSuggestions,
                builder: (context, suggestions) =>
                    _SuggestionsList(suggestions: suggestions),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SuggestionsList extends StatefulWidget {
  final List<MealSuggestion> suggestions;

  const _SuggestionsList({required this.suggestions});

  @override
  State<_SuggestionsList> createState() => _SuggestionsListState();
}

class _SuggestionsListState extends State<_SuggestionsList> {
  // null = "All Meals". Filters are derived from whatever meal types the
  // backend actually returns, same reasoning as SplitsScreen's category
  // filter - a new meal type shows up as a working filter with no frontend
  // change needed.
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final mealTypes = {for (final s in widget.suggestions) s.mealType}
        .toList()
      ..sort();
    final visible = _filter == null
        ? widget.suggestions
        : widget.suggestions.where((s) => s.mealType == _filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionEyebrow('Curated Ideas', color: AppColors.accent),
        const SizedBox(height: 4),
        Text('Suggested Meals', style: AppTypography.headlineLg),
        const SizedBox(height: AppSpacing.md),
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
                  onTap: () => setState(() => _filter = null),
                );
              }
              final mealType = mealTypes[i - 1];
              return PillChip(
                label: mealType,
                selected: _filter == mealType,
                onTap: () => setState(() => _filter = mealType),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionEyebrow('Meal Library'),
            Text('${visible.length} Meals',
                style: AppTypography.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (visible.isEmpty && widget.suggestions.isEmpty)
          const MascotEmptyState(
            pose: MascotPose.ready,
            title: 'No suggestions yet',
            message: 'Curated meal ideas will show up here once they\'re ready.',
          )
        else if (visible.isEmpty)
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
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final MealSuggestion suggestion;

  const _SuggestionCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MealSuggestionDetailScreen(
            controller: MealSuggestionActivationController(
                context.read<MealController>(), suggestion),
          ),
        ),
      ),
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
                  if (suggestion.description != null) ...[
                    const SizedBox(height: 4),
                    Text(suggestion.description!,
                        style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/silen_button.dart';
import 'create_exercise_sheet.dart';
import 'exercise_focus.dart';
import 'exercise_form_button.dart';
import 'exercises_models.dart';
import 'exercises_repository.dart';

/// Search-and-pick sheet backed by `GET /api/exercises`. Shared by the split
/// builder (picking an exercise for a day) and the live-workout swap/add
/// action, so the search UX is built once.
///
/// Opens on a personalised "suggested for you" list (ranked server-side from the
/// user's equipment and experience) and switches to search results as soon as
/// they type, so building a custom split starts from sensible picks rather than
/// a blank list.
///
/// When the split builder supplies the day's [dayTitle]/[dayFocus] and the
/// [existingExerciseGroups]/[excludeExerciseIds] already on it, the opening list
/// is instead scoped to that day: muscle groups named in the title lead, and a
/// generically titled day falls back to the groups of the exercises already
/// added. Callers that pass none of these (the live-workout swap/add sheet) keep
/// the generic "suggested for you" behaviour.
///
/// A search that finds nothing falls back to "did you mean" picks (names a
/// typo or two away), and when even those miss, asks the user to add the
/// exercise with its full details - which then comes back as the pick.
///
/// Returns the picked [ExerciseSummary], or null if the sheet was dismissed.
Future<ExerciseSummary?> showExercisePickerSheet(
  BuildContext context, {
  String? title,
  String? dayTitle,
  String? dayFocus,
  List<String> existingExerciseGroups = const [],
  Set<String> excludeExerciseIds = const {},
}) {
  return showModalBottomSheet<ExerciseSummary>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (_) => ExercisePickerSheet(
      title: title,
      dayTitle: dayTitle,
      dayFocus: dayFocus,
      existingExerciseGroups: existingExerciseGroups,
      excludeExerciseIds: excludeExerciseIds,
    ),
  );
}

class ExercisePickerSheet extends StatefulWidget {
  final String? title;

  /// Current custom-split day context, used to focus the opening suggestions.
  final String? dayTitle;
  final String? dayFocus;

  /// Coarse muscle groups of exercises already on the day, most recently added
  /// first - the fallback signal when the day title names no muscle.
  final List<String> existingExerciseGroups;

  /// Exercises already on the day, hidden from the suggestions so the list
  /// offers something new.
  final Set<String> excludeExerciseIds;

  const ExercisePickerSheet({
    super.key,
    this.title,
    this.dayTitle,
    this.dayFocus,
    this.existingExerciseGroups = const [],
    this.excludeExerciseIds = const {},
  });

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  bool _isLoading = false;
  String? _error;
  List<ExerciseSummary> _results = const [];

  /// "Did you mean" picks, loaded only when a search returns nothing.
  List<ExerciseSummary> _closeMatches = const [];

  /// The query [_results] (and [_closeMatches]) belong to, so a slow response
  /// for an older query never replaces the one on screen.
  String _resultsQuery = '';

  /// Ranked picks for this user, loaded once and shown until they start typing.
  List<ExerciseSummary> _suggestions = const [];
  bool _loadingSuggestions = true;

  /// Muscle groups this sheet's day points at (title intent first, then the
  /// exercises already added). Empty means the generic best-for-you list.
  late final ExerciseFocus _focus;

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focus = resolveExerciseFocus(
      title: widget.dayTitle,
      focus: widget.dayFocus,
      existingExerciseGroups: widget.existingExerciseGroups,
    );
    _loadSuggestions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      // Ask for extra when filtering out exercises already on the day, so the
      // list still fills its visible slots.
      final results = await context.read<ExercisesRepository>().suggestions(
            muscleGroups: _focus.isEmpty ? null : _focus.muscleGroups,
            limit: widget.excludeExerciseIds.isEmpty ? 12 : 24,
          );
      if (!mounted) return;
      setState(() {
        _suggestions = results
            .where((e) => !widget.excludeExerciseIds.contains(e.exerciseId))
            .take(12)
            .toList();
        _loadingSuggestions = false;
      });
    } catch (_) {
      // Suggestions are a convenience, not the only way through this sheet - the
      // search box below still works - so a failure here is deliberately silent
      // rather than replacing the picker with an error.
      if (!mounted) return;
      setState(() => _loadingSuggestions = false);
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      // Clearing the box returns to the suggestion list.
      setState(() {
        _results = const [];
        _closeMatches = const [];
        _resultsQuery = '';
        _error = null;
        _isLoading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repository = context.read<ExercisesRepository>();
      final results = await repository.search(search: query);
      // Nothing matched as typed - look for names a typo away before
      // offering to add it. Best-effort: on failure the add prompt shows.
      var closeMatches = const <ExerciseSummary>[];
      if (results.isEmpty) {
        try {
          closeMatches = await repository.closeMatches(query);
        } catch (_) {}
      }
      if (!mounted || query != _searchController.text.trim()) return;
      setState(() {
        _results = results;
        _closeMatches = closeMatches;
        _resultsQuery = query;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || query != _searchController.text.trim()) return;
      setState(() {
        _error = e.userMessage;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || query != _searchController.text.trim()) return;
      setState(() {
        _error = ApiException.genericMessage;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            left: AppSpacing.marginMobile,
            right: AppSpacing.marginMobile,
            top: AppSpacing.marginMobile,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title ?? 'Choose an exercise',
                style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _searchController,
              autofocus: false,
              onChanged: _onQueryChanged,
              decoration: const InputDecoration(
                hintText: 'Search exercises',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: _buildResults(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_isSearching) return _buildSearchResults();
    if (_loadingSuggestions) return _buildSpinner();
    return _buildSuggestionList();
  }

  Widget _buildSpinner() {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }

  /// Names the focus when the day said it, otherwise points at what the user
  /// has already been adding, and falls back to the generic heading when the
  /// day gives no signal at all.
  String get _suggestionHeading {
    if (_focus.fromTitle) {
      final groups =
          _focus.muscleGroups.map((g) => g.toUpperCase()).join(' & ');
      return 'SUGGESTED FOR $groups';
    }
    if (_focus.muscleGroups.isNotEmpty) return 'MORE FOR THIS DAY';
    return 'SUGGESTED FOR YOU';
  }

  String get _suggestionBadge =>
      _focus.isEmpty || _focus.fromTitle ? 'Suggested' : 'For this day';

  Widget _buildSuggestionList() {
    if (_suggestions.isEmpty) {
      return Center(
        child: Text('Search for an exercise above.',
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant)),
      );
    }
    return ListView.separated(
      itemCount: _suggestions.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xxs),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Text(_suggestionHeading,
                style:
                    AppTypography.labelCaps.copyWith(color: AppColors.accent)),
          );
        }
        return _ExerciseTile(
          exercise: _suggestions[index - 1],
          trailing: _suggestionBadge,
          trailingColor: AppColors.accent,
        );
      },
    );
  }

  Widget _buildSearchResults() {
    if (_isLoading) return _buildSpinner();
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: _search, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_results.isEmpty && _closeMatches.isEmpty) return _buildAddPrompt();
    final didYouMean = _results.isEmpty;
    final rows = didYouMean ? _closeMatches : _results;
    return ListView.separated(
      itemCount: rows.length + (didYouMean ? 2 : 1),
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xxs),
      itemBuilder: (context, index) {
        if (didYouMean) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No exact match for “$_resultsQuery”.',
                      style: AppTypography.bodyMd
                          .copyWith(color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: AppSpacing.xs),
                  Text('DID YOU MEAN',
                      style: AppTypography.labelCaps
                          .copyWith(color: AppColors.accent)),
                ],
              ),
            );
          }
          index -= 1;
        }
        if (index == rows.length) return _buildAddFooter();
        return _ExerciseTile(exercise: rows[index]);
      },
    );
  }

  /// Neither the search nor the "did you mean" pass found anything: the
  /// exercise isn't in the library, so the way forward is adding it.
  Widget _buildAddPrompt() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fitness_center_rounded,
                size: 32, color: AppColors.onSurfaceVariant),
            const SizedBox(height: AppSpacing.sm),
            Text('“$_resultsQuery” isn\'t in the library yet',
                textAlign: TextAlign.center, style: AppTypography.headlineSm),
            const SizedBox(height: AppSpacing.xxs),
            Text(
                'Add it with its muscle group, equipment and movement type, '
                'and it works like any other exercise in your splits and '
                'progress.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.md),
            PrimaryPillButton(
              label: 'Add exercise',
              icon: Icons.add_rounded,
              onPressed: _addCustom,
            ),
          ],
        ),
      ),
    );
  }

  /// Under a result list, for when what's listed is close but not it.
  Widget _buildAddFooter() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: TextButton.icon(
        onPressed: _addCustom,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text('Not listed? Add “$_resultsQuery”',
            overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Future<void> _addCustom() async {
    final created =
        await showCreateExerciseSheet(context, initialName: _resultsQuery);
    if (created != null && mounted) Navigator.of(context).pop(created);
  }
}

class _ExerciseTile extends StatelessWidget {
  final ExerciseSummary exercise;

  /// Optional right-hand badge, used to mark a row as a suggestion.
  final String? trailing;
  final Color? trailingColor;

  const _ExerciseTile({
    required this.exercise,
    this.trailing,
    this.trailingColor,
  });

  @override
  Widget build(BuildContext context) {
    final detail = [
      exercise.muscleGroup,
      if (exercise.equipmentType != null) exercise.equipmentType,
    ].whereType<String>().join(' • ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(exercise.name, style: AppTypography.bodyMd),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(detail,
              style: AppTypography.labelSm
                  .copyWith(color: AppColors.onSurfaceVariant)),
          // Why this exercise was picked for them - only present on suggestions.
          if (exercise.matchReason != null) ...[
            const SizedBox(height: 2),
            Text(exercise.matchReason!,
                style: AppTypography.labelSm.copyWith(color: AppColors.accent)),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExerciseFormButton(
              exerciseName: exercise.name, demoUrl: exercise.demoVideoUrl),
          if ((trailing ?? (exercise.isCustom ? 'Yours' : null))
              case final badge?) ...[
            const SizedBox(width: AppSpacing.xxs),
            Text(badge,
                style: AppTypography.labelCaps.copyWith(
                    color: trailingColor ?? AppColors.onSurfaceVariant)),
          ],
        ],
      ),
      onTap: () => Navigator.of(context).pop(exercise),
    );
  }
}

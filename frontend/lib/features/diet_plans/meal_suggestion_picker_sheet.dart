import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../meals/meal_controller.dart';
import '../meals/meal_models.dart';
import '../meals/meal_recommendation.dart';
import '../meals/meal_repository.dart';

/// Search-and-pick sheet backed by `GET /api/meals/suggestions` - the
/// diet-plan-builder equivalent of `ExercisePickerSheet`. [mealType], when
/// given, pre-filters the list (the slot's own type is still independently
/// stored on the DietPlanMeal row - a Breakfast slot may hold any suggestion).
///
/// Results are ordered by [rankMealMatches], so the sheet opens on the meal that
/// best fits the user's own targets and what's left in their day, with the
/// reason spelled out, instead of an alphabetical dump of the whole library.
///
/// Returns the picked [MealSuggestion], or null if the sheet was dismissed.
Future<MealSuggestion?> showMealSuggestionPickerSheet(
  BuildContext context, {
  String? mealType,
}) {
  return showModalBottomSheet<MealSuggestion>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (_) => MealSuggestionPickerSheet(initialMealType: mealType),
  );
}

class MealSuggestionPickerSheet extends StatefulWidget {
  final String? initialMealType;

  const MealSuggestionPickerSheet({super.key, this.initialMealType});

  @override
  State<MealSuggestionPickerSheet> createState() => _MealSuggestionPickerSheetState();
}

class _MealSuggestionPickerSheetState extends State<MealSuggestionPickerSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  bool _isLoading = true;
  String? _error;
  List<MealSuggestion> _all = const [];
  String? _mealTypeFilter;

  /// The selected day's composed totals, when they're already loaded. Passing
  /// them in lets the ranking weigh what's actually left in the user's day
  /// (calories and protein), not just their static targets.
  MealDay? _day;

  @override
  void initState() {
    super.initState();
    _mealTypeFilter = widget.initialMealType;
    _day = context.read<MealController>().state.data;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() {}));
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final suggestions = await context.read<MealRepository>().getSuggestions();
      if (!mounted) return;
      setState(() {
        _all = suggestions;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = ApiException.genericMessage;
        _isLoading = false;
      });
    }
  }

  /// The library filtered by the search box and meal-type chip, then ranked
  /// best-first for this user. Ranking (rather than sorting by name) is what
  /// turns a flat catalog into a suggestion.
  List<MealMatch> get _rankedFiltered {
    final query = _searchController.text.trim().toLowerCase();
    final matching = _all.where((s) {
      if (_mealTypeFilter != null && s.mealType != _mealTypeFilter) return false;
      if (query.isEmpty) return true;
      return s.title.toLowerCase().contains(query);
    }).toList();

    return rankMealMatches(matching, day: _day);
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
            Text('Choose a meal', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _searchController,
              autofocus: false,
              onChanged: _onQueryChanged,
              decoration: const InputDecoration(
                hintText: 'Search meals',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _mealTypeFilter == null,
                    onTap: () => setState(() => _mealTypeFilter = null),
                  ),
                  for (final type in kMealTypes) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    _FilterChip(
                      label: type,
                      selected: _mealTypeFilter == type,
                      onTap: () => setState(() => _mealTypeFilter = type),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 380,
              child: _buildResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final results = _rankedFiltered;
    if (results.isEmpty) {
      return Center(
        child: Text('No meals match this filter.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xxs),
      itemBuilder: (context, index) {
        final match = results[index];
        final suggestion = match.suggestion;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Row(
            children: [
              Expanded(
                  child: Text(suggestion.title, style: AppTypography.bodyMd)),
              // The list is already ranked best-first, so the top row is the
              // suggestion - labelling it makes that visible instead of implied.
              if (index == 0) ...[
                const SizedBox(width: AppSpacing.xs),
                Text('BEST MATCH',
                    style: AppTypography.labelCaps
                        .copyWith(color: AppColors.accent)),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${suggestion.mealType} • ${suggestion.caloriesKcal} kcal • '
                '${suggestion.proteinG}g protein',
                style: AppTypography.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              // Why this meal is being offered, in plain language.
              Text(match.reason,
                  style: AppTypography.labelSm.copyWith(color: AppColors.accent)),
            ],
          ),
          isThreeLine: true,
          onTap: () => Navigator.of(context).pop(suggestion),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(label,
            style: AppTypography.labelSm.copyWith(
                color: selected ? AppColors.onAccent : AppColors.onSurfaceVariant)),
      ),
    );
  }
}

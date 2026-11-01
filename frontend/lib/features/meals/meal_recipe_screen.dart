import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/skeleton.dart';
import 'meal_models.dart';
import 'meal_repository.dart';

/// Opens [MealRecipeScreen] for one meal suggestion.
Future<void> openMealRecipe(BuildContext context,
        {required String mealSuggestionId, required String title}) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          MealRecipeScreen(mealSuggestionId: mealSuggestionId, title: title),
    ));

/// A meal's ingredients (tick them off while shopping or cooking) and its
/// numbered steps. Reached from a meal suggestion, a diet plan day, and the
/// active plan on the Nutrition screen.
class MealRecipeScreen extends StatefulWidget {
  final String mealSuggestionId;
  final String title;

  const MealRecipeScreen(
      {super.key, required this.mealSuggestionId, required this.title});

  @override
  State<MealRecipeScreen> createState() => _MealRecipeScreenState();
}

class _MealRecipeScreenState extends State<MealRecipeScreen> {
  ResourceState<MealRecipe> _state = const ResourceState.loading();
  final _checked = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const ResourceState.loading());
    try {
      final recipe = await context
          .read<MealRepository>()
          .getRecipe(widget.mealSuggestionId);
      if (mounted) setState(() => _state = ResourceState.data(recipe));
    } on ApiException catch (e) {
      if (mounted) setState(() => _state = ResourceState.error(e.userMessage));
    } catch (_) {
      if (mounted) {
        setState(() =>
            _state = const ResourceState.error("Couldn't load the recipe."));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.title,
            style: AppTypography.headlineSm,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.gutterMobile),
          child: ResourceBuilder<MealRecipe>(
            state: _state,
            onRetry: _load,
            skeleton: const SkeletonDetail(rows: 4),
            builder: (context, recipe) => _body(recipe),
          ),
        ),
      ),
    );
  }

  Widget _body(MealRecipe recipe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recipe.mealType.isNotEmpty)
          SectionEyebrow(recipe.mealType, color: AppColors.accent),
        const SizedBox(height: AppSpacing.sm),
        Text(recipe.title, style: AppTypography.headlineLg),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${recipe.caloriesKcal} kcal · P${recipe.proteinG} '
          'C${recipe.carbsG} F${recipe.fatsG}',
          style:
              AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
        ),
        if (recipe.description?.trim().isNotEmpty == true) ...[
          const SizedBox(height: AppSpacing.md),
          Text(recipe.description!, style: AppTypography.bodyMd),
        ],
        if (recipe.isEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            child: Text(
              'No recipe for this meal yet. Its macros above are what to aim for.',
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
        if (recipe.ingredients.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                  child: Text('INGREDIENTS', style: AppTypography.labelCaps)),
              Text('${_checked.length}/${recipe.ingredients.length}',
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < recipe.ingredients.length; i++)
                  InkWell(
                    onTap: () => setState(() => _checked.contains(i)
                        ? _checked.remove(i)
                        : _checked.add(i)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.cardPadding, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _checked.contains(i)
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            size: 20,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              recipe.ingredients[i],
                              style: AppTypography.bodyMd.copyWith(
                                color: _checked.contains(i)
                                    ? AppColors.onSurfaceVariant
                                    : AppColors.onSurface,
                                decoration: _checked.contains(i)
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (recipe.steps.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('STEPS', style: AppTypography.labelCaps),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < recipe.steps.length; i++) ...[
            SectionCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle),
                    child: Text('${i + 1}',
                        style: AppTypography.labelCaps
                            .copyWith(color: AppColors.onAccent)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child:
                          Text(recipe.steps[i], style: AppTypography.bodyMd)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
        if (recipe.servingSuggestion?.trim().isNotEmpty == true) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.restaurant_rounded,
                  size: 16, color: AppColors.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(recipe.servingSuggestion!,
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

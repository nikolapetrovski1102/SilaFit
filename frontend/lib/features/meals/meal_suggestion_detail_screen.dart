import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import 'meal_controller.dart';
import 'meal_models.dart';

/// One curated meal's detail + activate action - mirrors SplitDetailScreen:
/// a hero summary, then a single primary button that flips from
/// "Activate This Meal" to a disabled "Added to Plan" once it fires.
class MealSuggestionDetailScreen extends StatefulWidget {
  final MealSuggestionActivationController controller;

  const MealSuggestionDetailScreen({super.key, required this.controller});

  @override
  State<MealSuggestionDetailScreen> createState() =>
      _MealSuggestionDetailScreenState();
}

class _MealSuggestionDetailScreenState
    extends State<MealSuggestionDetailScreen> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final ok = await widget.controller.activate();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${widget.controller.suggestion.title} added to today\'s plan.')));
    } else if (widget.controller.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.actionError!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = widget.controller.suggestion;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(suggestion.title, style: AppTypography.headlineSm)),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutterMobile),
            child: _DetailBody(
                suggestion: suggestion,
                controller: widget.controller,
                onActivate: _activate),
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final MealSuggestion suggestion;
  final MealSuggestionActivationController controller;
  final VoidCallback onActivate;

  const _DetailBody(
      {required this.suggestion,
      required this.controller,
      required this.onActivate});

  @override
  Widget build(BuildContext context) {
    final today = context.read<MealController>().selectedDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionEyebrow(suggestion.mealType, color: AppColors.accent),
        const SizedBox(height: AppSpacing.sm),
        Text(suggestion.title, style: AppTypography.headlineLg),
        const SizedBox(height: AppSpacing.md),
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
        const SizedBox(height: AppSpacing.md),
        if (suggestion.description != null) ...[
          Text(suggestion.description!, style: AppTypography.bodyMd),
          const SizedBox(height: AppSpacing.md),
        ],
        SectionCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: _MacroStat(
                          label: 'Protein', grams: suggestion.proteinG)),
                  Expanded(
                      child:
                          _MacroStat(label: 'Carbs', grams: suggestion.carbsG)),
                  Expanded(
                      child: _MacroStat(label: 'Fats', grams: suggestion.fatsG)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryPillButton(
          label: controller.activated
              ? 'Added to Plan'
              : 'Activate This Meal',
          icon: controller.activated
              ? Icons.check_rounded
              : Icons.add_circle_outline_rounded,
          isLoading: controller.isActivating,
          onPressed: controller.activated ? null : onActivate,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          controller.activated
              ? 'Mark it logged from the Nutrition tab once you\'ve eaten it.'
              : 'Adds this to ${DateFormat('EEEE, MMM d').format(today)} as a planned meal.',
          textAlign: TextAlign.center,
          style: AppTypography.labelSm
              .copyWith(color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _MacroStat extends StatelessWidget {
  final String label;
  final int grams;

  const _MacroStat({required this.label, required this.grams});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${grams}g', style: AppTypography.headlineSm),
        const SizedBox(height: 2),
        Text(label.toUpperCase(),
            style: AppTypography.labelCaps
                .copyWith(color: AppColors.onSurfaceVariant)),
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

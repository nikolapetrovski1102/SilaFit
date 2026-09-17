import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import '../meals/meal_models.dart';
import 'diet_plan_controller.dart';
import 'diet_plan_models.dart';
import 'meal_suggestion_picker_sheet.dart';

/// Build/edit screen for one day within a diet plan the user owns - day
/// header (title) plus its meal-slot list. A brand-new day (no
/// [dietPlanDayId]) saves its header first, same gating as
/// [DietPlanBuilderScreen] itself: the meal list only appears once the day
/// exists server-side.
class DietPlanDayEditorScreen extends StatefulWidget {
  final DietPlanBuilderController builderController;
  final String dietPlanId;
  final String? dietPlanDayId;

  const DietPlanDayEditorScreen({
    super.key,
    required this.builderController,
    required this.dietPlanId,
    this.dietPlanDayId,
  });

  @override
  State<DietPlanDayEditorScreen> createState() => _DietPlanDayEditorScreenState();
}

class _DietPlanDayEditorScreenState extends State<DietPlanDayEditorScreen> {
  late final TextEditingController _title;
  String? _dietPlanDayId;

  @override
  void initState() {
    super.initState();
    _dietPlanDayId = widget.dietPlanDayId;
    final day = _findDay()?.day;
    _title = TextEditingController(text: day?.title ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DietPlanDayWithMeals? _findDay() {
    if (_dietPlanDayId == null) return null;
    final days = widget.builderController.detail?.days ?? const [];
    for (final day in days) {
      if (day.day.dietPlanDayId == _dietPlanDayId) return day;
    }
    return null;
  }

  Future<void> _saveHeader() async {
    final existingDays = widget.builderController.detail?.days ?? const [];
    final dayIndex = _findDay()?.day.dayIndex ?? existingDays.length + 1;
    final ok = await widget.builderController.saveDay(
      dietPlanDayId: _dietPlanDayId,
      dayIndex: dayIndex,
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      _dietPlanDayId ??= _findLatestDayId(existingDays.length);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Day saved.')));
      setState(() {});
    } else if (widget.builderController.actionError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.builderController.actionError!)));
    }
  }

  // After creating a brand-new day, the controller has just reloaded the
  // detail - the new day is whichever one we didn't have before.
  String? _findLatestDayId(int previousCount) {
    final days = widget.builderController.detail?.days ?? const [];
    if (days.length <= previousCount) return null;
    final sorted = [...days]..sort((a, b) => a.day.dayIndex.compareTo(b.day.dayIndex));
    return sorted.last.day.dietPlanDayId;
  }

  Future<void> _deleteDay() async {
    final id = _dietPlanDayId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this day?'),
        content: const Text('Every meal on this day goes with it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await widget.builderController.deleteDay(id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else if (widget.builderController.actionError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.builderController.actionError!)));
    }
  }

  Future<void> _addMeal() async {
    final dayId = _dietPlanDayId;
    if (dayId == null) return;
    final mealType = await _promptMealType();
    if (mealType == null || !mounted) return;
    final suggestion = await showMealSuggestionPickerSheet(context, mealType: mealType);
    if (suggestion == null || !mounted) return;
    final existing = _findDay()?.meals ?? const [];
    final ok = await widget.builderController.saveMeal(
      dietPlanDayId: dayId,
      mealType: mealType,
      mealSuggestionId: suggestion.mealSuggestionId,
      sortOrder: existing.length,
    );
    if (!mounted) return;
    if (!ok && widget.builderController.actionError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.builderController.actionError!)));
    } else {
      setState(() {});
    }
  }

  Future<void> _editMeal(DietPlanMeal meal) async {
    final suggestion =
        await showMealSuggestionPickerSheet(context, mealType: meal.mealType);
    if (suggestion == null || !mounted) return;
    final ok = await widget.builderController.saveMeal(
      dietPlanMealId: meal.dietPlanMealId,
      dietPlanDayId: meal.dietPlanDayId,
      mealType: meal.mealType,
      mealSuggestionId: suggestion.mealSuggestionId,
      sortOrder: meal.sortOrder,
    );
    if (!mounted) return;
    if (!ok && widget.builderController.actionError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.builderController.actionError!)));
    } else {
      setState(() {});
    }
  }

  Future<void> _deleteMeal(String dietPlanMealId) async {
    final ok = await widget.builderController.deleteMeal(dietPlanMealId);
    if (!mounted) return;
    if (!ok && widget.builderController.actionError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.builderController.actionError!)));
    } else {
      setState(() {});
    }
  }

  Future<String?> _promptMealType() {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Which meal slot?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in kMealTypes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(type),
                onTap: () => Navigator.of(context).pop(type),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_dietPlanDayId == null ? 'New Day' : 'Edit Day',
            style: AppTypography.headlineSm),
        actions: [
          if (_dietPlanDayId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _deleteDay,
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.builderController,
        builder: (context, _) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutterMobile),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title (optional)'),
                ),
                const SizedBox(height: AppSpacing.sm),
                PrimaryPillButton(
                  label: _dietPlanDayId == null ? 'Create day' : 'Save changes',
                  icon: Icons.check_rounded,
                  isLoading: widget.builderController.isSaving,
                  onPressed: _saveHeader,
                ),
                if (_dietPlanDayId != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SectionEyebrow('Meals'),
                      TextButton.icon(
                        onPressed: _addMeal,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add meal'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildMealList(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMealList() {
    final meals = [...(_findDay()?.meals ?? const <DietPlanMeal>[])]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (meals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('No meals yet - tap "Add meal" to build this day.',
            style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final meal in meals) ...[
          SectionCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(meal.mealType.toUpperCase(),
                          style: AppTypography.labelCaps
                              .copyWith(color: AppColors.accent)),
                      Text(meal.title, style: AppTypography.bodyMd),
                      Text('${meal.caloriesKcal} kcal',
                          style: AppTypography.labelSm
                              .copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _editMeal(meal),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: () => _deleteMeal(meal.dietPlanMealId),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import '../../core/widgets/skeleton.dart';
import 'diet_plan_controller.dart';
import 'diet_plan_day_editor_screen.dart';
import 'diet_plan_models.dart';
import '../../l10n/l10n.dart';

const _kPeriodTypes = ['Weekly', 'Monthly'];

/// Build/edit screen for a diet plan the user owns. A brand-new plan (no
/// [DietPlanBuilderController.dietPlanId]) starts on the header form only;
/// once the header is saved for the first time, the day list appears below
/// it - same gating as [SplitBuilderScreen].
class DietPlanBuilderScreen extends StatefulWidget {
  final DietPlanBuilderController controller;

  const DietPlanBuilderScreen({super.key, required this.controller});

  @override
  State<DietPlanBuilderScreen> createState() => _DietPlanBuilderScreenState();
}

class _DietPlanBuilderScreenState extends State<DietPlanBuilderScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _duration;

  String _periodType = _kPeriodTypes.first;

  @override
  void initState() {
    super.initState();
    final existing = widget.controller.detail?.plan;
    _name = TextEditingController(text: existing?.name ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _duration =
        TextEditingController(text: (existing?.durationDays ?? 7).toString());
    _periodType = existing?.periodType ?? _kPeriodTypes.first;
    if (widget.controller.dietPlanId != null) {
      Future.microtask(widget.controller.load);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _saveHeader() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Give your plan a name.'))));
      return;
    }
    final duration = int.tryParse(_duration.text.trim()) ?? 7;
    final ok = await widget.controller.saveHeader(
      name: name,
      periodType: _periodType,
      durationDays: duration.clamp(1, 31),
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Plan saved.'))));
      setState(() {});
    } else if (widget.controller.actionError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.controller.actionError!)));
    }
  }

  Future<void> _deletePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete plan?')),
        content: Text(
            tr('This removes the plan and every day/meal in it. This can\'t be undone.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel'))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await widget.controller.deletePlan();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else if (widget.controller.actionError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.controller.actionError!)));
    }
  }

  Future<void> _openDay({String? dietPlanDayId}) async {
    final dietPlanId = widget.controller.dietPlanId;
    if (dietPlanId == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DietPlanDayEditorScreen(
        builderController: widget.controller,
        dietPlanId: dietPlanId,
        dietPlanDayId: dietPlanDayId,
      ),
    ));
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
            widget.controller.dietPlanId == null ? tr('New Diet Plan') : tr('Edit Diet Plan'),
            style: AppTypography.headlineSm),
        actions: [
          if (widget.controller.dietPlanId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _deletePlan,
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.gutterMobile),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionEyebrow(tr('Plan details')),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(labelText: tr('Name')),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _description,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: tr('Description (optional)')),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _periodType,
                        decoration: InputDecoration(labelText: tr('Period')),
                        items: [
                          for (final period in _kPeriodTypes)
                            DropdownMenuItem(value: period, child: Text(tr(period))),
                        ],
                        onChanged: (value) =>
                            setState(() => _periodType = value ?? _periodType),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _duration,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: tr('Days (1-31)')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryPillButton(
                  label: widget.controller.dietPlanId == null
                      ? tr('Create plan')
                      : tr('Save changes'),
                  icon: Icons.check_rounded,
                  isLoading: widget.controller.isSaving,
                  onPressed: _saveHeader,
                ),
                if (widget.controller.dietPlanId != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SectionEyebrow(tr('Plan days')),
                      TextButton.icon(
                        onPressed: () => _openDay(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(tr('Add day')),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildDayList(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayList() {
    final days = widget.controller.detail?.days ?? const [];
    if (widget.controller.loadState != null && !widget.controller.loadState!.hasData) {
      return const SkeletonList(count: 4);
    }
    if (days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(tr('No days yet - add your first plan day.'),
            style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in days..sort((a, b) => a.day.dayIndex.compareTo(b.day.dayIndex))) ...[
          _DayRow(
            day: day,
            onTap: () => _openDay(dietPlanDayId: day.day.dietPlanDayId),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  final DietPlanDayWithMeals day;
  final VoidCallback onTap;

  const _DayRow({required this.day, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SectionCard(
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text('${day.day.dayIndex}',
                  style: AppTypography.labelCaps.copyWith(color: AppColors.onAccent)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(day.day.title ?? tr('Day {n}', {'n': day.day.dayIndex}),
                      style: AppTypography.bodyMd),
                  Text(trPlural(day.meals.length, '{n} meal', '{n} meals'),
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

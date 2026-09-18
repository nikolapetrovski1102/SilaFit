import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import '../auth/widgets/auth_blob_background.dart';
import '../exercises/exercise_picker_sheet.dart';
import 'splits_controller.dart';
import 'splits_models.dart';
import 'widgets/reorder_sheet.dart';

/// Build/edit screen for one day within a split the user owns - day header
/// (title/focus/rest toggle) plus its exercise list. A brand-new day (no
/// [splitDayId]) saves its header first, same gating as [SplitBuilderScreen]
/// itself: the exercise list only appears once the day exists server-side.
class SplitDayEditorScreen extends StatefulWidget {
  final SplitBuilderController builderController;
  final String splitId;
  final String? splitDayId;

  const SplitDayEditorScreen({
    super.key,
    required this.builderController,
    required this.splitId,
    this.splitDayId,
  });

  @override
  State<SplitDayEditorScreen> createState() => _SplitDayEditorScreenState();
}

class _SplitDayEditorScreenState extends State<SplitDayEditorScreen> {
  static const _defaultEstimatedMinutes = 60;

  late final TextEditingController _title;
  late final TextEditingController _focus;
  late final TextEditingController _hours;
  late final TextEditingController _minutes;
  bool _isRestDay = false;
  String? _splitDayId;

  @override
  void initState() {
    super.initState();
    _splitDayId = widget.splitDayId;
    final day = _findDay()?.day;
    final totalMinutes = day?.estimatedMinutes ?? _defaultEstimatedMinutes;
    _title = TextEditingController(text: day?.title ?? '');
    _focus = TextEditingController(text: day?.focusLabel ?? '');
    _hours = TextEditingController(text: (totalMinutes ~/ 60).toString());
    _minutes = TextEditingController(text: (totalMinutes % 60).toString());
    _isRestDay = day?.isRestDay ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _focus.dispose();
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  SplitDayWithExercises? _findDay() {
    if (_splitDayId == null) return null;
    final days = widget.builderController.detail?.days ?? const [];
    for (final day in days) {
      if (day.day.splitDayId == _splitDayId) return day;
    }
    return null;
  }

  Future<void> _saveHeader() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give this day a title.')));
      return;
    }
    final existingDays = widget.builderController.detail?.days ?? const [];
    final dayIndex = _findDay()?.day.dayIndex ?? existingDays.length + 1;
    final hours =
        int.tryParse(_hours.text.trim()) ?? _defaultEstimatedMinutes ~/ 60;
    final minutes = hours * 60 + (int.tryParse(_minutes.text.trim()) ?? 0);
    final ok = await widget.builderController.saveDay(
      splitDayId: _splitDayId,
      dayIndex: dayIndex,
      title: title,
      focusLabel: _focus.text.trim().isEmpty ? null : _focus.text.trim(),
      estimatedMinutes: minutes,
      isRestDay: _isRestDay,
    );
    if (!mounted) return;
    if (ok) {
      _splitDayId ??= _findLatestDayId(existingDays.length);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Day saved.')));
      setState(() {});
    } else if (widget.builderController.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.builderController.actionError!)));
    }
  }

  // After creating a brand-new day, the controller has just reloaded the
  // detail - the new day is whichever one we didn't have before.
  String? _findLatestDayId(int previousCount) {
    final days = widget.builderController.detail?.days ?? const [];
    if (days.length <= previousCount) return null;
    final sorted = [...days]
      ..sort((a, b) => a.day.dayIndex.compareTo(b.day.dayIndex));
    return sorted.last.day.splitDayId;
  }

  Future<void> _deleteDay() async {
    final id = _splitDayId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this day?'),
        content: const Text('Every exercise on this day goes with it.'),
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
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.builderController.actionError!)));
    }
  }

  Future<void> _addExercise() async {
    final dayId = _splitDayId;
    if (dayId == null) return;

    // Feed the picker the current day so it can suggest on-focus exercises: the
    // title's named muscles lead, then whatever the user has already added
    // (most recent first) for generically titled days. Exercises already on the
    // day are hidden so the list offers something new.
    final existing = _findDay()?.exercises ?? const <SplitDayExercise>[];
    final existingGroups = existing.reversed
        .map((e) => e.muscleGroup)
        .where((group) => group.isNotEmpty)
        .toList();

    final exercise = await showExercisePickerSheet(
      context,
      title: 'Add exercise',
      dayTitle: _title.text,
      dayFocus: _focus.text,
      existingExerciseGroups: existingGroups,
      excludeExerciseIds: existing.map((e) => e.exerciseId).toSet(),
    );
    if (exercise == null || !mounted) return;
    final targets = await _promptSetsReps();
    if (targets == null || !mounted) return;
    final ok = await widget.builderController.saveDayExercise(
      splitDayId: dayId,
      exerciseId: exercise.exerciseId,
      sortOrder: existing.length,
      targetSets: targets.$1,
      targetRepsLow: targets.$2,
      targetRepsHigh: targets.$3,
    );
    if (!mounted) return;
    if (!ok && widget.builderController.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.builderController.actionError!)));
    } else {
      setState(() {});
    }
  }

  Future<void> _editExercise(SplitDayExercise exercise) async {
    final targets = await _promptSetsReps(
      initialSets: exercise.targetSets,
      initialLow: exercise.targetRepsLow,
      initialHigh: exercise.targetRepsHigh,
    );
    if (targets == null || !mounted) return;
    final ok = await widget.builderController.saveDayExercise(
      splitDayExerciseId: exercise.splitDayExerciseId,
      splitDayId: _splitDayId!,
      exerciseId: exercise.exerciseId,
      sortOrder: exercise.sortOrder,
      targetSets: targets.$1,
      targetRepsLow: targets.$2,
      targetRepsHigh: targets.$3,
    );
    if (!mounted) return;
    if (!ok && widget.builderController.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.builderController.actionError!)));
    } else {
      setState(() {});
    }
  }

  Future<void> _reorderExercises() async {
    final dayId = _splitDayId;
    if (dayId == null) return;
    final exercises = [...?_findDay()?.exercises]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final order = await showReorderSheet<SplitDayExercise>(
      context,
      title: 'Reorder exercises',
      subtitle: 'Press and drag the handle to change what comes next.',
      items: exercises,
      idOf: (e) => e.splitDayExerciseId,
      titleOf: (e) => e.name,
      subtitleOf: (e) =>
          '${e.targetSets} x ${e.targetRepsLow}-${e.targetRepsHigh}',
    );
    if (order == null || !mounted) return;
    final ok = await widget.builderController.reorderDayExercises(
        dayId, order.map((e) => e.splitDayExerciseId).toList());
    if (!mounted) return;
    if (!ok && widget.builderController.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.builderController.actionError!)));
    } else {
      setState(() {});
    }
  }

  Future<void> _deleteExercise(String splitDayExerciseId) async {
    final ok =
        await widget.builderController.deleteDayExercise(splitDayExerciseId);
    if (!mounted) return;
    if (!ok && widget.builderController.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.builderController.actionError!)));
    } else {
      setState(() {});
    }
  }

  Future<(int, int, int)?> _promptSetsReps({
    int initialSets = 3,
    int initialLow = 8,
    int initialHigh = 12,
  }) {
    final sets = TextEditingController(text: initialSets.toString());
    final low = TextEditingController(text: initialLow.toString());
    final high = TextEditingController(text: initialHigh.toString());
    return showDialog<(int, int, int)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sets and reps'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: sets,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sets'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: TextField(
                controller: low,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Reps low'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: TextField(
                controller: high,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Reps high'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop((
              int.tryParse(sets.text.trim()) ?? initialSets,
              int.tryParse(low.text.trim()) ?? initialLow,
              int.tryParse(high.text.trim()) ?? initialHigh,
            )),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // See the matching comment in SplitBuilderScreen - lets the blob
      // backdrop bleed all the way behind the (transparent) AppBar instead
      // of stopping at the body's normal top edge.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_splitDayId == null ? 'New Day' : 'Edit Day',
            style: AppTypography.headlineSm),
        actions: [
          if (_splitDayId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _deleteDay,
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // See the matching comment in SplitBuilderScreen - layout 3 keeps
          // every blob inside the visible viewport for a full-page
          // scrolling form like this one.
          const Positioned.fill(child: AuthBlobBackground(layout: 3)),
          AnimatedBuilder(
            animation: widget.builderController,
            builder: (context, _) => SafeArea(
              child: SingleChildScrollView(
                // Extra top inset makes up for `extendBodyBehindAppBar`,
                // same reasoning as SplitBuilderScreen's padding.
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutterMobile,
                  AppSpacing.gutterMobile + kToolbarHeight,
                  AppSpacing.gutterMobile,
                  AppSpacing.gutterMobile,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _focus,
                      decoration:
                          const InputDecoration(labelText: 'Focus (optional)'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Rest day'),
                      value: _isRestDay,
                      onChanged: (value) => setState(() => _isRestDay = value),
                    ),
                    if (!_isRestDay) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _hours,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: 'Hours'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: TextField(
                              controller: _minutes,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: 'Minutes'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    PrimaryPillButton(
                      label:
                          _splitDayId == null ? 'Create day' : 'Save changes',
                      icon: Icons.check_rounded,
                      isLoading: widget.builderController.isSaving,
                      onPressed: _saveHeader,
                    ),
                    if (_splitDayId != null && !_isRestDay) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SectionEyebrow('Exercises'),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if ((_findDay()?.exercises.length ?? 0) > 1)
                                IconButton(
                                  icon: const Icon(Icons.reorder_rounded,
                                      size: 20),
                                  tooltip: 'Reorder exercises',
                                  onPressed: _reorderExercises,
                                ),
                              TextButton.icon(
                                onPressed: _addExercise,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Add exercise'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _buildExerciseList(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseList() {
    final exercises = _findDay()?.exercises ?? const [];
    if (exercises.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('No exercises yet - tap "Add exercise" to build this day.',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.onSurfaceVariant)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final exercise in exercises) ...[
          SectionCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exercise.name, style: AppTypography.bodyMd),
                      Text(
                          '${exercise.targetSets} x ${exercise.targetRepsLow}-${exercise.targetRepsHigh}',
                          style: AppTypography.labelSm
                              .copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _editExercise(exercise),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: () => _deleteExercise(exercise.splitDayExerciseId),
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

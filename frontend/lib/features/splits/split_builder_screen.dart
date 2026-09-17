import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import '../../core/widgets/silen_slide_route.dart';
import '../auth/widgets/auth_blob_background.dart';
import '../today/today_controller.dart';
import 'split_day_editor_screen.dart';
import 'splits_controller.dart';
import 'splits_models.dart';

const _kLevels = ['Beginner', 'Intermediate', 'Advanced'];
const _kGoals = ['BuildMuscle', 'LoseFat', 'MaintainActive'];

String _goalLabel(String goal) => switch (goal) {
      'BuildMuscle' => 'Build muscle',
      'LoseFat' => 'Lose fat',
      'MaintainActive' => 'Stay active',
      _ => goal,
    };

/// Build/edit screen for a split the user owns. A brand-new split (no
/// [SplitBuilderController.splitId]) starts on the header form only; once
/// the header is saved for the first time, the day list appears below it.
class SplitBuilderScreen extends StatefulWidget {
  final SplitBuilderController controller;

  const SplitBuilderScreen({super.key, required this.controller});

  @override
  State<SplitBuilderScreen> createState() => _SplitBuilderScreenState();
}

class _SplitBuilderScreenState extends State<SplitBuilderScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _duration;

  String _level = _kLevels.first;
  String? _goal;
  bool _populatedFromExisting = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.controller.detail?.split;
    _name = TextEditingController(text: existing?.name ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _duration =
        TextEditingController(text: (existing?.durationDays ?? 7).toString());
    _level = existing?.level ?? _kLevels.first;
    _goal = existing?.recommendedGoal;
    _populatedFromExisting = existing != null;
    if (widget.controller.splitId != null) {
      // `detail` is still null here - the controller hasn't loaded yet - so
      // the fields above start empty even in edit mode. Fill them in once
      // `load()` resolves instead.
      widget.controller.addListener(_populateFromLoadedDetail);
      Future.microtask(widget.controller.load);
    }
  }

  void _populateFromLoadedDetail() {
    if (_populatedFromExisting) return;
    final existing = widget.controller.detail?.split;
    if (existing == null) return;
    _populatedFromExisting = true;
    _name.text = existing.name;
    _description.text = existing.description ?? '';
    _duration.text = existing.durationDays.toString();
    setState(() {
      _level = existing.level;
      _goal = existing.recommendedGoal;
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_populateFromLoadedDetail);
    _name.dispose();
    _description.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _saveHeader() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give your split a name.')));
      return;
    }
    final duration = int.tryParse(_duration.text.trim()) ?? 7;
    final ok = await widget.controller.saveHeader(
      name: name,
      category: 'Custom',
      level: _level,
      durationDays: duration.clamp(1, 14),
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      recommendedGoal: _goal,
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Split saved.')));
      setState(() {});
    } else if (widget.controller.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.actionError!)));
    }
  }

  Future<void> _deleteSplit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete split?'),
        content: const Text(
            'This removes the split and every day/exercise in it. This can\'t be undone.'),
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
    final ok = await widget.controller.deleteSplit();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else if (widget.controller.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.actionError!)));
    }
  }

  Future<void> _activateSplit() async {
    final ok = await widget.controller.activate();
    if (!mounted) return;
    if (ok) {
      // Home's dashboard is loaded once and cached, so without this the newly
      // activated split's session (and its exercises) would not appear until a
      // manual pull-to-refresh.
      context.read<TodayController>().load(force: true);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This is now your active split.')));
    } else if (widget.controller.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.actionError!)));
    }
  }

  Future<void> _openDay({String? splitDayId}) async {
    final splitId = widget.controller.splitId;
    if (splitId == null) return;
    await Navigator.of(context).push(SilenSlideRoute(
      builder: (_) => SplitDayEditorScreen(
        builderController: widget.controller,
        splitId: splitId,
        splitDayId: splitDayId,
      ),
    ));
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // Lets the blob backdrop bleed all the way behind the (transparent)
      // AppBar instead of stopping at the body's normal top edge - matching
      // how AuthBlobBackground reaches the true screen edges on
      // login/register, which have no AppBar to begin with.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
            widget.controller.splitId == null ? 'New Split' : 'Edit Split',
            style: AppTypography.headlineSm),
        actions: [
          if (widget.controller.splitId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _deleteSplit,
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layout 3 keeps every blob inside the visible viewport (unlike
          // login/register's step layouts, which push their third blob past
          // the bottom edge) - this screen's content scrolls to whatever
          // height it needs, so the background has to hold up on its own
          // all the way to the true bottom instead of relying on fixed
          // footer content to sit there.
          const Positioned.fill(child: AuthBlobBackground(layout: 3)),
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => SafeArea(
              child: SingleChildScrollView(
                // Extra top inset makes up for `extendBodyBehindAppBar`: the
                // AppBar itself no longer reserves this space, so the form
                // has to clear it manually to land back where it was.
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutterMobile,
                  AppSpacing.gutterMobile + kToolbarHeight,
                  AppSpacing.gutterMobile,
                  AppSpacing.gutterMobile,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionEyebrow('Split details'),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Description (optional)'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _level,
                            decoration:
                                const InputDecoration(labelText: 'Level'),
                            items: [
                              for (final level in _kLevels)
                                DropdownMenuItem(
                                    value: level, child: Text(level)),
                            ],
                            onChanged: (value) =>
                                setState(() => _level = value ?? _level),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            controller: _duration,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Days (1-14)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<String?>(
                      initialValue: _goal,
                      decoration:
                          const InputDecoration(labelText: 'Goal (optional)'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('No specific goal')),
                        for (final goal in _kGoals)
                          DropdownMenuItem(
                              value: goal, child: Text(_goalLabel(goal))),
                      ],
                      onChanged: (value) => setState(() => _goal = value),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PrimaryPillButton(
                      label: widget.controller.splitId == null
                          ? 'Create split'
                          : 'Save changes',
                      icon: Icons.check_rounded,
                      isLoading: widget.controller.isSaving,
                      onPressed: _saveHeader,
                    ),
                    // Only offered once the split actually exists server-side
                    // - a brand-new split needs its header saved first (that's
                    // what assigns `splitId`) before there's anything to
                    // activate.
                    if (widget.controller.splitId != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SecondaryPillButton(
                        label: widget.controller.activated
                            ? 'Split Activated'
                            : 'Activate This Split',
                        icon: widget.controller.activated
                            ? Icons.check_rounded
                            : Icons.play_arrow_rounded,
                        onPressed: widget.controller.isActivating ||
                                widget.controller.activated
                            ? null
                            : _activateSplit,
                      ),
                    ],
                    if (widget.controller.splitId != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SectionEyebrow('Workout days'),
                          TextButton.icon(
                            onPressed: () => _openDay(),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add day'),
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
        ],
      ),
    );
  }

  Widget _buildDayList() {
    final days = widget.controller.detail?.days ?? const [];
    if (widget.controller.loadState != null &&
        !widget.controller.loadState!.hasData) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    if (days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('No days yet - add your first training day.',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.onSurfaceVariant)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in days
          ..sort((a, b) => a.day.dayIndex.compareTo(b.day.dayIndex))) ...[
          _DayRow(
            day: day,
            onTap: () => _openDay(splitDayId: day.day.splitDayId),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  final SplitDayWithExercises day;
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
                color: day.day.isRestDay
                    ? AppColors.surfaceContainerHigh
                    : AppColors.accent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text('${day.day.dayIndex}',
                  style: AppTypography.labelCaps.copyWith(
                      color: day.day.isRestDay
                          ? AppColors.onSurfaceVariant
                          : AppColors.onAccent)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(day.day.title, style: AppTypography.bodyMd),
                  Text(
                      day.day.isRestDay
                          ? 'Rest day'
                          : '${day.exercises.length} exercises',
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

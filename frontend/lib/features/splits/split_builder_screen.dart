import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'widgets/ink_field.dart';
import 'widgets/reorder_sheet.dart';
import '../auth/widgets/auth_blob_background.dart';
import '../today/today_controller.dart';
import 'split_day_editor_screen.dart';
import 'splits_controller.dart';
import 'splits_models.dart';

const _kLevels = ['Beginner', 'Intermediate', 'Advanced'];
const _kGoals = ['BuildMuscle', 'LoseFat', 'MaintainActive'];
const _kMaxDays = 14;

String _goalLabel(String goal) => switch (goal) {
      'BuildMuscle' => 'Build muscle',
      'LoseFat' => 'Lose fat',
      'MaintainActive' => 'Stay active',
      _ => goal,
    };

/// Build/edit screen for a split the user owns, in the same "ink" style as
/// [SplitCreationWizardScreen]: the name is the big borderless title (saved
/// on submit or blur), the days sit under it as a plain list, and the rest
/// of the header (level, goal, length, description) lives in a details
/// sheet off the slim top bar. No AppBar, no footer buttons.
///
/// A brand-new split (no [SplitBuilderController.splitId]) shows just the
/// name; saving it creates the split and the day list appears.
class SplitBuilderScreen extends StatefulWidget {
  final SplitBuilderController controller;

  const SplitBuilderScreen({super.key, required this.controller});

  @override
  State<SplitBuilderScreen> createState() => _SplitBuilderScreenState();
}

class _SplitBuilderScreenState extends State<SplitBuilderScreen> {
  late final TextEditingController _name;
  final _nameFocus = FocusNode();

  String _description = '';
  int _durationDays = 7;
  String _level = _kLevels.first;
  String? _goal;
  bool _populatedFromExisting = false;

  SplitBuilderController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final existing = _controller.detail?.split;
    _name = TextEditingController(text: existing?.name ?? '');
    _description = existing?.description ?? '';
    _durationDays = existing?.durationDays ?? 7;
    _level = existing?.level ?? _kLevels.first;
    _goal = existing?.recommendedGoal;
    _populatedFromExisting = existing != null;
    _nameFocus.addListener(_onNameFocusChanged);
    if (_controller.splitId != null) {
      // `detail` is still null here - the controller hasn't loaded yet - so
      // the fields above start empty even in edit mode. Fill them in once
      // `load()` resolves instead.
      _controller.addListener(_populateFromLoadedDetail);
      Future.microtask(_controller.load);
    }
  }

  void _populateFromLoadedDetail() {
    if (_populatedFromExisting) return;
    final existing = _controller.detail?.split;
    if (existing == null) return;
    _populatedFromExisting = true;
    _name.text = existing.name;
    setState(() {
      _description = existing.description ?? '';
      _durationDays = existing.durationDays;
      _level = existing.level;
      _goal = existing.recommendedGoal;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_populateFromLoadedDetail);
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _toastError() {
    final error = _controller.actionError;
    if (error != null) _toast(error);
  }

  void _onNameFocusChanged() {
    if (!_nameFocus.hasFocus) _commitName();
  }

  /// Saves the name if it changed; an emptied name snaps back instead.
  void _commitName() {
    final name = _name.text.trim();
    final saved = _controller.detail?.split.name;
    if (name.isEmpty) {
      if (saved != null) _name.text = saved;
      return;
    }
    if (name == saved) return;
    _saveHeader();
  }

  Future<void> _saveHeader() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('Give your split a name.');
      return;
    }
    final ok = await _controller.saveHeader(
      name: name,
      category: 'Custom',
      level: _level,
      durationDays: _durationDays.clamp(1, _kMaxDays),
      description: _description.trim().isEmpty ? null : _description.trim(),
      recommendedGoal: _goal,
    );
    if (!mounted) return;
    if (!ok) _toastError();
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
    final ok = await _controller.deleteSplit();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      _toastError();
    }
  }

  Future<void> _activateSplit() async {
    HapticFeedback.selectionClick();
    final ok = await _controller.activate();
    if (!mounted) return;
    if (ok) {
      // Home's dashboard is loaded once and cached, so without this the newly
      // activated split's session (and its exercises) would not appear until a
      // manual pull-to-refresh.
      context.read<TodayController>().load(force: true);
      _toast('This is now your active split.');
    } else {
      _toastError();
    }
  }

  Future<void> _openDay({String? splitDayId}) async {
    final splitId = _controller.splitId;
    if (splitId == null) return;
    _nameFocus.unfocus();
    // A cross-fade rather than the usual slide, so the day's title reads as
    // one piece of text growing into the editor's big title.
    await Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: kInkMorph + const Duration(milliseconds: 60),
      reverseTransitionDuration: kInkMorph,
      pageBuilder: (_, __, ___) => SplitDayEditorScreen(
        builderController: _controller,
        splitId: splitId,
        splitDayId: splitDayId,
      ),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ));
    if (!mounted) return;
    setState(() {});
  }

  List<SplitDayWithExercises> get _sortedDays => <SplitDayWithExercises>[
        ..._controller.detail?.days ?? const []
      ]..sort((a, b) => a.day.dayIndex.compareTo(b.day.dayIndex));

  Future<void> _reorderDays() async {
    final order = await showReorderSheet<SplitDayWithExercises>(
      context,
      title: 'Reorder days',
      subtitle: 'Press and drag the handle to change what comes next.',
      items: _sortedDays,
      idOf: (d) => d.day.splitDayId,
      titleOf: (d) => d.day.title,
      subtitleOf: (d) =>
          d.day.isRestDay ? 'Rest day' : '${d.exercises.length} exercises',
    );
    if (order == null || !mounted) return;
    final ok = await _controller
        .reorderDays(order.map((d) => d.day.splitDayId).toList());
    if (!mounted) return;
    if (!ok) _toastError();
  }

  Future<void> _showDetails() async {
    _nameFocus.unfocus();
    final before = (_description, _durationDays, _level, _goal);
    final description = TextEditingController(text: _description);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          void update(VoidCallback change) {
            setSheet(change);
            setState(() {});
          }

          return _DetailsSheet(
            description: description,
            durationDays: _durationDays,
            level: _level,
            goal: _goal,
            onDuration: (v) => update(() => _durationDays = v),
            onLevel: (v) => update(() => _level = v),
            onGoal: (v) => update(() => _goal = v),
          );
        },
      ),
    );
    _description = description.text;
    description.dispose();
    if (!mounted || _controller.splitId == null) return;
    if ((_description, _durationDays, _level, _goal) != before) _saveHeader();
  }

  String get _metaLine => [
        '$_durationDays ${_durationDays == 1 ? 'DAY' : 'DAYS'}',
        _level.toUpperCase(),
        if (_goal != null) _goalLabel(_goal!).toUpperCase(),
      ].join('  ·  ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: AuthBlobBackground(layout: 3)),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _nameFocus.unfocus,
                      child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.marginMobile,
                          AppSpacing.lg,
                          AppSpacing.marginMobile,
                          AppSpacing.xxl + MediaQuery.paddingOf(context).bottom,
                        ),
                        children: [
                          InkField(
                            controller: _name,
                            focusNode: _nameFocus,
                            hint: 'Name your split',
                            hero: true,
                            autofocus: _controller.splitId == null,
                            // Submitting blurs the field, and the blur saves.
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _buildMeta(),
                          if (_controller.splitId != null) ...[
                            const SizedBox(height: AppSpacing.xxl),
                            _buildDays(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final exists = _controller.splitId != null;
    final activated = _controller.activated;
    return InkTopBar(
      actions: [
        InkSavingDot(visible: _controller.isSaving),
        if (exists)
          AnimatedSwitcher(
            duration: kInkQuick,
            child: TextButton.icon(
              key: ValueKey(activated),
              onPressed:
                  _controller.isActivating || activated ? null : _activateSplit,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                visualDensity: VisualDensity.compact,
              ),
              icon: Icon(
                  activated ? Icons.check_rounded : Icons.play_arrow_rounded,
                  size: 18),
              label: Text(activated ? 'Active' : 'Activate'),
            ),
          ),
        if (exists)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: 'More',
            onSelected: (value) => switch (value) {
              'details' => _showDetails(),
              'reorder' => _reorderDays(),
              'delete' => _deleteSplit(),
              _ => null,
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'details', child: Text('Details')),
              if ((_controller.detail?.days.length ?? 0) > 1)
                const PopupMenuItem(
                    value: 'reorder', child: Text('Reorder days')),
              const PopupMenuItem(value: 'delete', child: Text('Delete split')),
            ],
          ),
      ],
    );
  }

  /// Length, level and goal as one quiet line - tapping it opens the rest.
  Widget _buildMeta() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _controller.splitId == null ? null : _showDetails,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_metaLine,
              style: AppTypography.labelCaps
                  .copyWith(color: AppColors.onSurfaceVariant)),
          if (_description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(_description.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _buildDays() {
    final detail = _controller.detail;
    if (detail == null) {
      final error = _controller.loadState?.error;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: error == null
            ? const Center(
                child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))
            : GestureDetector(
                onTap: _controller.load,
                child: Text('$error  Tap to retry.',
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ),
      );
    }
    final days = _sortedDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < days.length; i++)
          _Entrance(
            key: ValueKey(days[i].day.splitDayId),
            index: i,
            child: _DayTile(
              day: days[i],
              onTap: () => _openDay(splitDayId: days[i].day.splitDayId),
            ),
          ),
        if (days.length < _kMaxDays)
          _Entrance(
            index: days.length,
            child: _AddDayTile(onTap: () => _openDay()),
          ),
      ],
    );
  }
}

/// Fades and lifts [child] in once, a beat after the item before it.
class _Entrance extends StatelessWidget {
  final int index;
  final Widget child;

  const _Entrance({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final delay = (index * 40).clamp(0, 240);
    final total = kInkMorph.inMilliseconds + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (_, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

class _DayTile extends StatelessWidget {
  final SplitDayWithExercises day;
  final VoidCallback onTap;

  const _DayTile({required this.day, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final rest = day.day.isRestDay;
    final exercises = [...day.exercises]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final subtitle = rest
        ? 'Rest day'
        : exercises.isEmpty
            ? 'No exercises yet'
            : exercises.map((e) => e.name).join('  ·  ');
    final eyebrow = AppTypography.labelCaps
        .copyWith(color: rest ? AppColors.onSurfaceVariant : AppColors.accent);
    final title = AppTypography.headlineMd
        .copyWith(color: rest ? AppColors.onSurfaceVariant : null);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkTextHero(
                    tag: dayEyebrowHeroTag(day.day.splitDayId),
                    text: 'DAY ${day.day.dayIndex}',
                    style: eyebrow,
                    child: Text('DAY ${day.day.dayIndex}', style: eyebrow),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  InkTextHero(
                    tag: dayTitleHeroTag(day.day.splitDayId),
                    text: day.day.title,
                    style: title,
                    child: Text(day.day.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: title),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySm
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

class _AddDayTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddDayTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.add_rounded, color: AppColors.accent),
            const SizedBox(width: AppSpacing.xs),
            Text('Add day',
                style:
                    AppTypography.headlineMd.copyWith(color: AppColors.accent)),
          ],
        ),
      ),
    );
  }
}

/// The header fields the main screen doesn't show inline.
class _DetailsSheet extends StatelessWidget {
  final TextEditingController description;
  final int durationDays;
  final String level;
  final String? goal;
  final ValueChanged<int> onDuration;
  final ValueChanged<String> onLevel;
  final ValueChanged<String?> onGoal;

  const _DetailsSheet({
    required this.description,
    required this.durationDays,
    required this.level,
    required this.goal,
    required this.onDuration,
    required this.onLevel,
    required this.onGoal,
  });

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(text,
            style: AppTypography.labelCaps
                .copyWith(color: AppColors.onSurfaceVariant)),
      );

  Widget _choice(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) {
          HapticFeedback.selectionClick();
          onTap();
        },
      );

  @override
  Widget build(BuildContext context) {
    final bodyStyle = AppTypography.bodyLg;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.marginMobile,
          AppSpacing.xl,
          AppSpacing.marginMobile,
          AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _label('DESCRIPTION'),
            TextField(
              controller: description,
              minLines: 1,
              maxLines: 4,
              style: bodyStyle,
              cursorColor: AppColors.accent,
              textCapitalization: TextCapitalization.sentences,
              decoration: inkDecoration('What is this split for?', bodyStyle),
            ),
            const SizedBox(height: AppSpacing.xl),
            _label('LENGTH'),
            Row(
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  onPressed: durationDays > 1
                      ? () => onDuration(durationDays - 1)
                      : null,
                ),
                SizedBox(
                  width: 72,
                  child: Text('$durationDays',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineMd),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: durationDays < _kMaxDays
                      ? () => onDuration(durationDays + 1)
                      : null,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(durationDays == 1 ? 'day' : 'days',
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _label('LEVEL'),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final l in _kLevels)
                  _choice(l, l == level, () => onLevel(l)),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _label('GOAL'),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _choice('Any', goal == null, () => onGoal(null)),
                for (final g in _kGoals)
                  _choice(_goalLabel(g), g == goal, () => onGoal(g)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

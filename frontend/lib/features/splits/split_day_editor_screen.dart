import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../auth/widgets/auth_blob_background.dart';
import '../exercises/exercise_focus.dart';
import '../exercises/exercises_models.dart';
import '../exercises/exercises_repository.dart';
import 'splits_controller.dart';
import 'splits_models.dart';
import 'widgets/ink_field.dart';
import 'widgets/muscle_focus_field.dart';
import 'widgets/reorder_sheet.dart';

// New exercises start on the same target as the creation wizard's; tapping
// a chip tunes it.
const _kDefaultSets = 3;
const _kDefaultRepsLow = 8;
const _kDefaultRepsHigh = 12;
const _kDefaultEstimatedMinutes = 60;
const _kDurations = [30, 45, 60, 75, 90, 120];

/// Build/edit screen for one day within a split the user owns, in the same
/// "ink" style as [SplitCreationWizardScreen]: the day's title is the big
/// borderless field, focus/length/rest sit in one quiet row beneath it, and
/// exercises are added from an inline search that flies each pick into the
/// day's chips. Everything saves as it changes - no AppBar, no save button.
///
/// A brand-new day (no [splitDayId]) starts on a preset title; committing
/// it creates the day, and the exercise search appears.
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
  late final TextEditingController _title;
  List<String> _focusTargets = [];
  final _search = TextEditingController();
  final _titleFocus = FocusNode();
  final _focusLabelFocus = FocusNode();
  final _searchFocus = FocusNode();

  late final ExercisesRepository _exercises;
  int _estimatedMinutes = _kDefaultEstimatedMinutes;
  bool _isRestDay = false;
  String? _splitDayId;

  /// Every write goes through here, one at a time: the controller reloads
  /// after each save and skips a reload that overlaps another.
  Future<void> _queue = Future.value();

  // Exercise search.
  List<ExerciseSummary> _suggestions = const [];
  List<ExerciseSummary> _results = const [];
  bool _searching = false;
  Timer? _debounce;
  int _queryToken = 0;

  // Optimistic chips: picked but not yet saved, still flying, or being
  // removed.
  final _pendingAdds = <ExerciseSummary>[];
  final _inFlight = <String>{};
  final _removing = <String>{};
  final _chipKeys = <String, GlobalKey>{};
  final _rowKeys = <String, GlobalKey>{};
  final _flights = <OverlayEntry>[];

  SplitBuilderController get _controller => widget.builderController;

  @override
  void initState() {
    super.initState();
    _exercises = context.read<ExercisesRepository>();
    _splitDayId = widget.splitDayId;
    final day = _findDay()?.day;
    _estimatedMinutes = day?.estimatedMinutes ?? _kDefaultEstimatedMinutes;
    _isRestDay = day?.isRestDay ?? false;
    _focusTargets = parseMuscleTargets(day?.focusLabel);
    if (day != null) {
      _title = TextEditingController(text: day.title);
      _loadSuggestions();
    } else {
      // Preset, fully selected - typing replaces it, submitting keeps it.
      final preset = 'Awesome Day ${_dayIndex()}';
      _title = TextEditingController.fromValue(TextEditingValue(
        text: preset,
        selection: TextSelection(baseOffset: 0, extentOffset: preset.length),
      ));
    }
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus) _saveHeader();
    });
    _focusLabelFocus.addListener(() {
      if (!_focusLabelFocus.hasFocus) _saveHeader();
    });
    // Searching collapses the header into the top bar.
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final flight in _flights) {
      if (flight.mounted) flight.remove();
    }
    _title.dispose();
    _search.dispose();
    _titleFocus.dispose();
    _focusLabelFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  SplitDayWithExercises? _findDay() {
    if (_splitDayId == null) return null;
    final days = _controller.detail?.days ?? const [];
    for (final day in days) {
      if (day.day.splitDayId == _splitDayId) return day;
    }
    return null;
  }

  int _dayIndex() =>
      _findDay()?.day.dayIndex ?? (_controller.detail?.days.length ?? 0) + 1;

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _toastError() {
    final error = _controller.actionError;
    if (error != null) _toast(error);
  }

  Future<bool> _enqueue(Future<bool> Function() write) {
    final result = _queue.then((_) => write());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /* ------------------------------- day header ------------------------------ */

  /// Saves the header if anything in it changed - creating the day the
  /// first time. An emptied title snaps back instead.
  Future<void> _saveHeader() {
    if (_title.text.trim().isEmpty) {
      final day = _findDay()?.day;
      if (day != null) _title.text = day.title;
      return Future.value();
    }
    // Compared inside the queue, against the day as the last write left it -
    // a submit then a blur must not create the day twice.
    return _enqueue(() async {
      final title = _title.text.trim();
      final focus = formatMuscleTargets(_focusTargets);
      final day = _findDay()?.day;
      if (title.isEmpty ||
          (day != null &&
              day.title == title &&
              (day.focusLabel ?? '') == focus &&
              day.estimatedMinutes == _estimatedMinutes &&
              day.isRestDay == _isRestDay)) {
        return true;
      }
      final previousCount = _controller.detail?.days.length ?? 0;
      final ok = await _controller.saveDay(
        splitDayId: _splitDayId,
        dayIndex: _dayIndex(),
        title: title,
        focusLabel: focus.isEmpty ? null : focus,
        estimatedMinutes: _estimatedMinutes,
        isRestDay: _isRestDay,
      );
      if (!mounted) return ok;
      if (ok) {
        _splitDayId ??= _findLatestDayId(previousCount);
        setState(() {});
        if (day == null ||
            day.title != title ||
            (day.focusLabel ?? '') != focus) {
          _loadSuggestions();
        }
      } else {
        _toastError();
      }
      return ok;
    });
  }

  // After creating a brand-new day, the controller has just reloaded the
  // detail - the new day is whichever one we didn't have before.
  String? _findLatestDayId(int previousCount) {
    final days = _controller.detail?.days ?? const [];
    if (days.length <= previousCount) return null;
    final sorted = [...days]
      ..sort((a, b) => a.day.dayIndex.compareTo(b.day.dayIndex));
    return sorted.last.day.splitDayId;
  }

  void _submitTitle() {
    _saveHeader();
    if (_isRestDay) {
      _titleFocus.unfocus();
    } else {
      // Straight on to exercises, keyboard still up.
      _searchFocus.requestFocus();
    }
  }

  void _toggleRest() {
    HapticFeedback.selectionClick();
    setState(() => _isRestDay = !_isRestDay);
    _saveHeader();
  }

  Future<void> _pickDuration() async {
    FocusScope.of(context).unfocus();
    final options = {..._kDurations, _estimatedMinutes}.toList()..sort();
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
              AppSpacing.xl, AppSpacing.marginMobile, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ABOUT HOW LONG?',
                  style: AppTypography.labelCaps
                      .copyWith(color: AppColors.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final minutes in options)
                    ChoiceChip(
                      label: Text(_formatMinutes(minutes)),
                      selected: minutes == _estimatedMinutes,
                      showCheckmark: false,
                      onSelected: (_) => Navigator.of(context).pop(minutes),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == _estimatedMinutes || !mounted) return;
    setState(() => _estimatedMinutes = picked);
    _saveHeader();
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
    final ok = await _enqueue(() => _controller.deleteDay(id));
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      _toastError();
    }
  }

  /* -------------------------------- exercises ------------------------------ */

  List<SplitDayExercise> get _savedExercises => [...?_findDay()?.exercises]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Set<String> get _takenIds => {
        for (final e in _savedExercises) e.exerciseId,
        for (final e in _pendingAdds) e.exerciseId,
      };

  List<ExerciseSummary> get _visible {
    final taken = _takenIds;
    final source = _search.text.trim().isEmpty ? _suggestions : _results;
    return source.where((e) => !taken.contains(e.exerciseId)).toList();
  }

  Future<void> _loadSuggestions() async {
    // The title's named muscles lead, then whatever the user has already
    // added (most recent first) for generically titled days.
    final existingGroups = _savedExercises.reversed
        .map((e) => e.muscleGroup)
        .where((group) => group.isNotEmpty)
        .toList();
    final focus = resolveExerciseFocus(
      title: _title.text,
      focus: formatMuscleTargets(_focusTargets),
      existingExerciseGroups: existingGroups,
    );
    try {
      final results = await _exercises.suggestions(
        muscleGroups: focus.isEmpty ? null : focus.muscleGroups,
        limit: 16,
      );
      if (!mounted) return;
      setState(() => _suggestions = results);
    } catch (_) {
      // Suggestions are only a head start - search still works without them.
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _queryToken++;
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce =
        Timer(const Duration(milliseconds: 220), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final token = ++_queryToken;
    try {
      final results = await _exercises.search(search: query);
      if (!mounted || token != _queryToken) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || token != _queryToken) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
    }
  }

  void _submitSearch() {
    final items = _visible;
    if (_search.text.trim().isEmpty || items.isEmpty) {
      _searchFocus.unfocus();
    } else {
      _add(items.first);
    }
  }

  Future<void> _add(ExerciseSummary exercise) async {
    final dayId = _splitDayId;
    final id = exercise.exerciseId;
    if (dayId == null || _takenIds.contains(id)) return;
    final from = overlayRectOf(context, _rowKeys[id]);
    HapticFeedback.selectionClick();

    final sortOrder = _savedExercises.length + _pendingAdds.length;
    setState(() {
      _pendingAdds.add(exercise);
      if (from != null) _inFlight.add(id);
    });
    if (_search.text.isNotEmpty) {
      _search.clear();
      _onSearchChanged('');
    }

    _enqueue(() => _controller.saveDayExercise(
          splitDayId: dayId,
          exerciseId: id,
          sortOrder: sortOrder,
          targetSets: _kDefaultSets,
          targetRepsLow: _kDefaultRepsLow,
          targetRepsHigh: _kDefaultRepsHigh,
        )).then((ok) {
      if (!mounted) return;
      setState(() => _pendingAdds.remove(exercise));
      if (!ok) _toastError();
    });

    if (from == null) return;
    // The chip is laid out (invisibly) this frame; fly into wherever it
    // landed, then reveal it.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final to = overlayRectOf(context, _chipKeys[id]);
    if (to == null) {
      setState(() => _inFlight.remove(id));
      return;
    }
    late final OverlayEntry flight;
    flight = flyExercise(context, label: exercise.name, from: from, to: to,
        onLanded: () {
      _flights.remove(flight);
      if (mounted) setState(() => _inFlight.remove(id));
    });
    _flights.add(flight);
  }

  void _remove(SplitDayExercise exercise) {
    HapticFeedback.selectionClick();
    final id = exercise.splitDayExerciseId;
    setState(() => _removing.add(id));
    _enqueue(() => _controller.deleteDayExercise(id)).then((ok) {
      if (!mounted) return;
      setState(() => _removing.remove(id));
      if (!ok) _toastError();
    });
  }

  Future<void> _editExercise(SplitDayExercise exercise) async {
    FocusScope.of(context).unfocus();
    final targets = await _promptSetsReps(
      initialSets: exercise.targetSets,
      initialLow: exercise.targetRepsLow,
      initialHigh: exercise.targetRepsHigh,
    );
    if (targets == null || !mounted) return;
    final ok = await _enqueue(() => _controller.saveDayExercise(
          splitDayExerciseId: exercise.splitDayExerciseId,
          splitDayId: _splitDayId!,
          exerciseId: exercise.exerciseId,
          sortOrder: exercise.sortOrder,
          targetSets: targets.$1,
          targetRepsLow: targets.$2,
          targetRepsHigh: targets.$3,
        ));
    if (!mounted) return;
    if (!ok) _toastError();
  }

  Future<void> _reorderExercises() async {
    final dayId = _splitDayId;
    if (dayId == null) return;
    FocusScope.of(context).unfocus();
    final order = await showReorderSheet<SplitDayExercise>(
      context,
      title: 'Reorder exercises',
      subtitle: 'Press and drag the handle to change what comes next.',
      items: _savedExercises,
      idOf: (e) => e.splitDayExerciseId,
      titleOf: (e) => e.name,
      subtitleOf: (e) =>
          '${e.targetSets} x ${e.targetRepsLow}-${e.targetRepsHigh}',
    );
    if (order == null || !mounted) return;
    final ok = await _enqueue(() => _controller.reorderDayExercises(
        dayId, order.map((e) => e.splitDayExerciseId).toList()));
    if (!mounted) return;
    if (!ok) _toastError();
  }

  Future<(int, int, int)?> _promptSetsReps({
    int initialSets = _kDefaultSets,
    int initialLow = _kDefaultRepsLow,
    int initialHigh = _kDefaultRepsHigh,
  }) {
    final sets = TextEditingController(text: initialSets.toString());
    final low = TextEditingController(text: initialLow.toString());
    final high = TextEditingController(text: initialHigh.toString());
    Widget number(TextEditingController controller, String label) => Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(labelText: label),
          ),
        );
    return showDialog<(int, int, int)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sets and reps'),
        content: Row(
          children: [
            number(sets, 'Sets'),
            const SizedBox(width: AppSpacing.xs),
            number(low, 'Reps low'),
            const SizedBox(width: AppSpacing.xs),
            number(high, 'Reps high'),
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

  /* --------------------------------- build --------------------------------- */

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
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.marginMobile),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildCollapsibleHeader(),
                            Expanded(child: _buildBody()),
                          ],
                        ),
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
    final exists = _splitDayId != null;
    return InkTopBar(
      title: _buildCompactTitle(),
      actions: [
        InkSavingDot(visible: _controller.isSaving),
        if (exists && !_isRestDay && _savedExercises.length > 1)
          IconButton(
            icon: const Icon(Icons.reorder_rounded, size: 20),
            tooltip: 'Reorder exercises',
            onPressed: _reorderExercises,
          ),
        if (exists)
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            tooltip: 'Delete day',
            onPressed: _deleteDay,
          ),
      ],
    );
  }

  /// While the exercise search has focus the keyboard eats half the screen,
  /// so the header folds away and the day's title moves up into the top
  /// bar - leaving the room to the results.
  bool get _compact => _searchFocus.hasFocus;

  Widget _buildCompactTitle() {
    return IgnorePointer(
      child: AnimatedSlide(
        offset: _compact ? Offset.zero : const Offset(0, 0.4),
        duration: kInkQuick,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _compact ? 1 : 0,
          duration: kInkQuick,
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DAY ${_dayIndex()}',
                  style: AppTypography.labelCaps
                      .copyWith(color: AppColors.accent)),
              Text(
                _title.text.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    AppTypography.bodyLg.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsibleHeader() {
    // Kept in the tree while folded so the title/eyebrow heroes still fly.
    return ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.bottomCenter,
        heightFactor: _compact ? 0 : 1,
        duration: kInkQuick,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _compact ? 0 : 1,
          duration: kInkQuick,
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: _compact,
            child: Padding(
              padding: const EdgeInsets.only(
                  top: AppSpacing.lg, bottom: AppSpacing.xl),
              child: _buildHeader(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final id = _splitDayId;
    final eyebrowText = 'DAY ${_dayIndex()}';
    final eyebrowStyle = AppTypography.labelCaps.copyWith(
        color: _isRestDay ? AppColors.onSurfaceVariant : AppColors.accent);
    final eyebrow = Text(eyebrowText, style: eyebrowStyle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The day's settings ride on the eyebrow's line, so they cost no
        // height of their own.
        Row(
          children: [
            id == null
                ? eyebrow
                : InkTextHero(
                    tag: dayEyebrowHeroTag(id),
                    text: eyebrowText,
                    style: eyebrowStyle,
                    child: eyebrow,
                  ),
            const Spacer(),
            AnimatedSize(
              duration: kInkQuick,
              curve: Curves.easeOutCubic,
              child: _isRestDay
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: _MetaPill(
                        icon: Icons.schedule_rounded,
                        label: _formatMinutes(_estimatedMinutes),
                        onTap: _pickDuration,
                      ),
                    ),
            ),
            _MetaPill(
              icon: _isRestDay ? Icons.bedtime_rounded : Icons.bedtime_outlined,
              label: 'Rest',
              selected: _isRestDay,
              onTap: _toggleRest,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        InkField(
          controller: _title,
          focusNode: _titleFocus,
          hint: 'Name this day',
          hero: true,
          heroTag: id == null ? null : dayTitleHeroTag(id),
          autofocus: widget.splitDayId == null,
          textInputAction:
              _isRestDay ? TextInputAction.done : TextInputAction.next,
          keepFocusOnSubmit: true,
          onSubmitted: _submitTitle,
        ),
        const SizedBox(height: AppSpacing.lg),
        MuscleFocusField(
          targets: _focusTargets,
          focusNode: _focusLabelFocus,
          onChanged: (targets) {
            setState(() => _focusTargets = targets);
            // While focused, the blur saves; a chip dropped without focus
            // saves straight away.
            if (!_focusLabelFocus.hasFocus) _saveHeader();
          },
        ),
      ],
    );
  }

  Widget _buildBody() {
    final Widget child;
    if (_isRestDay) {
      child = _note('A rest day - nothing to plan. Recovery counts too.');
    } else if (_splitDayId == null) {
      child = _note('Name the day, then add its exercises.');
    } else {
      child = _buildExercises();
    }
    return AnimatedSwitcher(
      duration: kInkQuick,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(
        key: ValueKey('$_isRestDay-${_splitDayId != null}'),
        child: child,
      ),
    );
  }

  Widget _note(String text) => Align(
        alignment: Alignment.topLeft,
        child: Text(text,
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant)),
      );

  Widget _buildExercises() {
    final saved =
        _savedExercises.where((e) => !_removing.contains(e.splitDayExerciseId));
    final savedIds = {for (final e in saved) e.exerciseId};
    final pending = _pendingAdds.where((e) => !savedIds.contains(e.exerciseId));
    final hasChips = saved.isNotEmpty || pending.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: kInkQuick,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: hasChips
              ? Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 128),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final e in saved)
                            ExerciseChip(
                              key: _chipKeys.putIfAbsent(
                                  e.exerciseId, GlobalKey.new),
                              label: e.name,
                              detail:
                                  '${e.targetSets}×${e.targetRepsLow}–${e.targetRepsHigh}',
                              visible: !_inFlight.contains(e.exerciseId),
                              onTap: () => _editExercise(e),
                              onRemove: () => _remove(e),
                            ),
                          for (final e in pending)
                            ExerciseChip(
                              key: _chipKeys.putIfAbsent(
                                  e.exerciseId, GlobalKey.new),
                              label: e.name,
                              detail:
                                  '$_kDefaultSets×$_kDefaultRepsLow–$_kDefaultRepsHigh',
                              visible: !_inFlight.contains(e.exerciseId),
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        InkField(
          controller: _search,
          focusNode: _searchFocus,
          hint: 'Add exercise',
          style: AppTypography.headlineSm,
          textCapitalization: TextCapitalization.none,
          keepFocusOnSubmit: true,
          onChanged: _onSearchChanged,
          onSubmitted: _submitSearch,
        ),
        Expanded(child: _buildResults()),
      ],
    );
  }

  Widget _buildResults() {
    final items = _visible;
    final query = _search.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Only built while searching - an indeterminate bar keeps ticking
        // even when faded out.
        SizedBox(
          height: 2,
          child: _searching
              ? LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.accent,
                  backgroundColor: Colors.transparent,
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (query.isEmpty && items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text('SUGGESTED', style: AppTypography.labelCaps),
          ),
        Expanded(
          child: items.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: AnimatedOpacity(
                    opacity: query.isNotEmpty && !_searching ? 1 : 0,
                    duration: kInkQuick,
                    child: Text(
                      'No matches for "$query"',
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.only(
                      bottom:
                          AppSpacing.md + MediaQuery.paddingOf(context).bottom),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final exercise = items[i];
                    return ExerciseResultRow(
                      key: _rowKeys.putIfAbsent(
                          exercise.exerciseId, GlobalKey.new),
                      exercise: exercise,
                      onTap: () => _add(exercise),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

String _formatMinutes(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '${h}h';
  return '${h}h $m';
}

/// A small tappable pill for the day's settings row.
class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MetaPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.onAccent : AppColors.highEmphasis;
    return Material(
      color: selected ? AppColors.accent : AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: AppTypography.bodySm
                      .copyWith(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/silen_button.dart';
import '../auth/widgets/auth_blob_background.dart';
import '../exercises/exercise_focus.dart';
import '../exercises/exercises_models.dart';
import '../exercises/exercises_repository.dart';
import 'splits_repository.dart';
import 'widgets/ink_field.dart';

// The wizard no longer asks for these - every split it creates is the same
// shape, and the day-by-day flow below is where all the real customization
// happens. "Level 2" (of Beginner/Intermediate/Advanced) is Intermediate;
// 7 days always, so the day-by-day flow can let the user leave any of them
// as a rest day instead of the split's total length varying.
const _kLevel = 'Intermediate';
const _kDurationDays = 7;

// Every exercise added here starts on the same target; the split builder is
// where sets/reps get tuned, so the wizard never stops to ask.
const _kDefaultSets = 3;
const _kDefaultRepsLow = 8;
const _kDefaultRepsHigh = 12;

const _kIntro = Duration(milliseconds: 260);

// Line heights of the committed text: the split name as the title, then
// the current day's eyebrow + title beneath it. Both titles may wrap to two
// lines, so the slots below them are derived from measured line counts.
const double _kTitleLine = 34; // headlineLg
const double _kEyebrowLine = 14; // labelCaps
const double _kDayLine = 28; // headlineMd
const int _kMaxTitleLines = 2;

enum _Stage { name, dayTitle, exercises, done }

/// Builds a custom split on one screen with one text field (bottom rule only)
/// that keeps focus between steps, so the keyboard never drops:
///
/// 1. the split's name, as big type - committing it lifts the text up into
///    the screen's title;
/// 2. each day's title, in the same big field - committing it settles under
///    the split name as the day's heading;
/// 3. that day's exercises - the field shrinks to a search line, and tapping
///    a result flies it up into the day's chip list.
///
/// Saves are optimistic: every step animates immediately while the requests
/// chain behind it (split -> day -> exercise), so nothing waits on the
/// network.
class SplitCreationWizardScreen extends StatefulWidget {
  /// How many splits the user already owns - the default name is
  /// "Awesome Split {existingSplitCount + 1}".
  final int existingSplitCount;

  const SplitCreationWizardScreen({super.key, this.existingSplitCount = 0});

  @override
  State<SplitCreationWizardScreen> createState() =>
      _SplitCreationWizardScreenState();
}

class _AddedExercise {
  final ExerciseSummary exercise;
  Future<String?>? saved;
  bool landed;

  _AddedExercise(this.exercise, {required this.landed});
}

class _SplitCreationWizardScreenState extends State<SplitCreationWizardScreen>
    with TickerProviderStateMixin {
  late final SplitsRepository _splits;
  late final ExercisesRepository _exercises;

  final _input = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _intro;

  /// Fills the field's bottom line in on focus and drains it on blur.
  late final AnimationController _underline;

  _Stage _stage = _Stage.name;
  int _day = 1;
  String? _splitName;
  String? _dayTitle;

  /// Where the big input sits for the current layout (it follows the
  /// keyboard); captured into [_titleFrom]/[_dayFrom] at commit time so the
  /// morphing text starts exactly where the typed text was.
  double _heroTop = 120;
  double _titleFrom = 120;
  double _dayFrom = 120;

  /// Same idea for the big input's auto-scaled type size.
  double _heroSize = kHeroMaxSize;
  double _titleFromSize = kHeroMaxSize;
  double _dayFromSize = kHeroMaxSize;

  /// Bumped when the split itself fails to save and the flow restarts, so
  /// errors from requests chained off the dead split are ignored.
  int _generation = 0;
  Future<String?>? _splitId;
  Future<String?>? _dayId;
  final _pending = <Future<void>>[];

  /// Finished days -> whether each was a rest day.
  final _completedDays = <int, bool>{};

  final _added = <_AddedExercise>[];
  final _chipKeys = <String, GlobalKey>{};
  final _rowKeys = <String, GlobalKey>{};
  List<ExerciseSummary> _suggestions = const [];
  List<ExerciseSummary> _results = const [];
  bool _searching = false;
  Timer? _debounce;
  int _queryToken = 0;

  final _flights = <OverlayEntry>[];
  bool _finishing = false;

  String get _presetName => 'Awesome Split ${widget.existingSplitCount + 1}';
  String _presetDay(int day) => 'Awesome Day $day';

  @override
  void initState() {
    super.initState();
    _splits = context.read<SplitsRepository>();
    _exercises = context.read<ExercisesRepository>();
    _intro = AnimationController(vsync: this, duration: _kIntro)..forward();
    _underline = AnimationController(vsync: this, duration: kInkMorph);
    _focus.addListener(_onFocusChanged);
    _preset(_presetName);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final flight in _flights) {
      flight.remove();
    }
    _flights.clear();
    _intro.dispose();
    _underline.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focus.hasFocus) {
      _underline.forward();
    } else {
      _underline.reverse();
    }
  }

  /// Fills the field with [text] fully selected, so typing replaces it and
  /// submitting straight away keeps it.
  void _preset(String text) {
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: 0, extentOffset: text.length),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Registers a background save so "Done" can wait for it, and reports its
  /// failure - unless the flow has since restarted.
  void _track(Future<Object?> future, {VoidCallback? onError}) {
    final generation = _generation;
    _pending.add(future.then<void>((_) {}, onError: (Object e) {
      if (!mounted || generation != _generation) return;
      onError?.call();
      _toast(e is ApiException ? e.userMessage : ApiException.genericMessage);
    }));
  }

  /* --------------------------------- steps --------------------------------- */

  void _submit() {
    switch (_stage) {
      case _Stage.name:
        _commitName();
      case _Stage.dayTitle:
        _commitDay(rest: false);
      case _Stage.exercises:
        final visible = _visible;
        if (_input.text.trim().isEmpty) {
          _nextDay();
        } else if (visible.isNotEmpty) {
          _add(visible.first);
        }
      case _Stage.done:
        break;
    }
  }

  void _commitName() {
    final typed = _input.text.trim();
    final name = typed.isEmpty ? _presetName : typed;
    HapticFeedback.lightImpact();

    final split = _splits.createOrUpdate(
      name: name,
      category: 'Custom',
      level: _kLevel,
      durationDays: _kDurationDays,
    );
    _splitId = split;
    _track(split, onError: () => _restart(name));

    setState(() {
      _titleFrom = _heroTop;
      _titleFromSize = _heroSize;
      _splitName = name;
      _stage = _Stage.dayTitle;
    });
    _preset(_presetDay(_day));
    _intro.forward(from: 0);
    _focus.requestFocus();
  }

  /// The split itself failed to save - everything chained after it is dead,
  /// so go back to naming it (keeping what they typed).
  void _restart(String name) {
    setState(() {
      _generation++;
      _stage = _Stage.name;
      _day = 1;
      _splitName = null;
      _dayTitle = null;
      _completedDays.clear();
      _resetDayState();
    });
    _preset(name);
    _intro.forward(from: 0);
    _focus.requestFocus();
  }

  void _commitDay({required bool rest}) {
    final day = _day;
    final typed = _input.text.trim();
    final title = rest
        ? (typed.isEmpty || typed == _presetDay(day) ? 'Rest day' : typed)
        : (typed.isEmpty ? _presetDay(day) : typed);
    HapticFeedback.lightImpact();

    final dayId = _splitId!.then((splitId) => _splits.saveDay(
          splitId: splitId!,
          dayIndex: day,
          title: title,
          isRestDay: rest,
        ));
    _track(dayId);

    if (rest) {
      _completedDays[day] = true;
      _advance();
      return;
    }

    _dayId = dayId;
    setState(() {
      _dayFrom = _heroTop;
      _dayFromSize = _heroSize;
      _dayTitle = title;
      _stage = _Stage.exercises;
      _resetDayState();
    });
    _input.clear();
    _intro.forward(from: 0);
    _focus.requestFocus();
    _loadSuggestions(title);
  }

  void _nextDay() {
    HapticFeedback.lightImpact();
    _completedDays[_day] = false;
    _advance();
  }

  void _advance() {
    if (_day >= _kDurationDays) {
      _focus.unfocus();
      setState(() => _stage = _Stage.done);
      return;
    }
    setState(() {
      _day++;
      _dayTitle = null;
      _stage = _Stage.dayTitle;
      _resetDayState();
    });
    _preset(_presetDay(_day));
    _intro.forward(from: 0);
    _focus.requestFocus();
  }

  void _resetDayState() {
    _debounce?.cancel();
    _queryToken++;
    _added.clear();
    _chipKeys.clear();
    _rowKeys.clear();
    _suggestions = const [];
    _results = const [];
    _searching = false;
  }

  Future<void> _done() async {
    setState(() => _finishing = true);
    await Future.wait(_pending);
    if (mounted) Navigator.of(context).pop();
  }

  /* ------------------------------- exercises ------------------------------- */

  List<ExerciseSummary> get _visible {
    final taken = {for (final a in _added) a.exercise.exerciseId};
    final source = _input.text.trim().isEmpty ? _suggestions : _results;
    return source.where((e) => !taken.contains(e.exerciseId)).toList();
  }

  Future<void> _loadSuggestions(String dayTitle) async {
    final day = _day;
    final focus = resolveExerciseFocus(title: dayTitle);
    try {
      final results = await _exercises.suggestions(
        muscleGroups: focus.isEmpty ? null : focus.muscleGroups,
        limit: 16,
      );
      if (!mounted || day != _day || _stage != _Stage.exercises) return;
      setState(() => _suggestions = results);
    } catch (_) {
      // Suggestions are only a head start - search still works without them.
    }
  }

  void _onChanged(String value) {
    if (_stage != _Stage.exercises) return;
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
    _debounce = Timer(const Duration(milliseconds: 220), () => _search(query));
  }

  Future<void> _search(String query) async {
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

  Future<void> _add(ExerciseSummary exercise) async {
    final id = exercise.exerciseId;
    if (_added.any((a) => a.exercise.exerciseId == id)) return;
    final from = overlayRectOf(context, _rowKeys[id]);
    HapticFeedback.selectionClick();

    final entry = _AddedExercise(exercise, landed: from == null);
    final sortOrder = _added.length;
    final save = _dayId!.then((dayId) => _splits.saveDayExercise(
          splitDayId: dayId!,
          exerciseId: id,
          sortOrder: sortOrder,
          targetSets: _kDefaultSets,
          targetRepsLow: _kDefaultRepsLow,
          targetRepsHigh: _kDefaultRepsHigh,
        ));
    entry.saved = save;
    _track(save, onError: () => setState(() => _added.remove(entry)));

    setState(() => _added.add(entry));
    if (_input.text.isNotEmpty) {
      _input.clear();
      _onChanged('');
    }
    if (from == null) return;

    // The chip is laid out (invisibly) this frame; fly into wherever it
    // landed, then reveal it.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final to = overlayRectOf(context, _chipKeys[id]);
    if (to == null) {
      setState(() => entry.landed = true);
      return;
    }
    _fly(exercise.name, from, to, onLanded: () {
      if (mounted) setState(() => entry.landed = true);
    });
  }

  void _remove(_AddedExercise entry) {
    HapticFeedback.selectionClick();
    setState(() => _added.remove(entry));
    final saved = entry.saved;
    if (saved == null) return;
    // A failed save was already reported (and removed the chip itself).
    _track(saved.then<void>((savedId) async {
      if (savedId != null) await _splits.deleteDayExercise(savedId);
    }, onError: (_) {}));
  }

  void _fly(String label, Rect from, Rect to,
      {required VoidCallback onLanded}) {
    late final OverlayEntry flight;
    flight =
        flyExercise(context, label: label, from: from, to: to, onLanded: () {
      _flights.remove(flight);
      onLanded();
    });
    _flights.add(flight);
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            child: _stage == _Stage.done
                ? _buildSuccess(context)
                : KeyedSubtree(
                    key: const ValueKey('flow'),
                    child: _buildFlow(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlow() {
    return SafeArea(
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.marginMobile),
              child: LayoutBuilder(builder: (context, constraints) {
                final width = constraints.maxWidth;
                final titleLines = _splitName == null
                    ? 1
                    : _lineCount(_splitName!, AppTypography.headlineLg, width);
                final dayLines = _dayTitle == null
                    ? 1
                    : _lineCount(_dayTitle!, AppTypography.headlineMd, width);
                final dayEyebrowTop = titleLines * _kTitleLine + AppSpacing.lg;
                final dayTop = dayEyebrowTop + _kEyebrowLine + AppSpacing.xs;
                final exerciseTop =
                    dayTop + dayLines * _kDayLine + AppSpacing.xl;
                _heroTop = (constraints.maxHeight * 0.26)
                    .clamp(titleLines * _kTitleLine + AppSpacing.xxxl, 200.0);
                final inputTop =
                    _stage == _Stage.exercises ? exerciseTop : _heroTop;
                // Tapping anywhere empty drops the keyboard (and drains the
                // underline); tapping the field brings both back.
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _focus.unfocus,
                  child: Stack(
                    children: [
                      Positioned.fill(
                          child: _buildInputColumn(inputTop, width)),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: _buildHeaders(
                              dayEyebrowTop: dayEyebrowTop, dayTop: dayTop),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xxs,
          AppSpacing.marginMobile, AppSpacing.md),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _DayProgress(
              completed: _completedDays,
              current: _stage == _Stage.name ? null : _day,
            ),
          ),
        ],
      ),
    );
  }

  /// The committed text, drawn above the input column - the split name as
  /// the title and (while picking exercises) the day's heading.
  int _lineCount(String text, TextStyle style, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: _kMaxTitleLines,
    )..layout(maxWidth: width);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines.clamp(1, _kMaxTitleLines);
  }

  Widget _buildHeaders(
      {required double dayEyebrowTop, required double dayTop}) {
    final showDay = _stage == _Stage.exercises && _dayTitle != null;
    return Stack(
      children: [
        if (_splitName != null)
          Positioned.fill(
            child: InkMorphText(
              key: ValueKey('title-$_generation'),
              text: _splitName!,
              fromTop: _titleFrom,
              toTop: 0,
              fromStyle: heroStyle(_titleFromSize),
              toStyle: AppTypography.headlineLg,
            ),
          ),
        Positioned.fill(
          child: AnimatedSwitcher(
            // Zero-length in so the heading takes over from the typed text
            // on the exact same frame; only the outgoing day fades.
            duration: Duration.zero,
            reverseDuration: kInkQuick,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, -0.04),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: showDay
                ? Stack(
                    key: ValueKey('day-$_day-$_generation'),
                    children: [
                      Positioned(
                        top: dayEyebrowTop,
                        left: 0,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: kInkMorph,
                          curve: Curves.easeOut,
                          builder: (_, t, child) => Opacity(
                            opacity: t,
                            child: Transform.translate(
                                offset: Offset(0, 6 * (1 - t)), child: child),
                          ),
                          child: Text(
                            'DAY $_day OF $_kDurationDays',
                            style: AppTypography.labelCaps
                                .copyWith(color: AppColors.accent),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: InkMorphText(
                          text: _dayTitle!,
                          fromTop: _dayFrom,
                          toTop: dayTop,
                          fromStyle: heroStyle(_dayFromSize),
                          toStyle: AppTypography.headlineMd,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('no-day')),
          ),
        ),
      ],
    );
  }

  /// The one text field, and what hangs off it. Its position in this tree
  /// never changes, so it keeps focus (and the keyboard) across every step.
  Widget _buildInputColumn(double inputTop, double width) {
    final intro = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    final picking = _stage == _Stage.exercises;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: kInkMorph,
          curve: Curves.easeOutCubic,
          height: inputTop,
        ),
        AnimatedSize(
          duration: kInkQuick,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: picking && _added.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 136),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final entry in _added)
                            ExerciseChip(
                              key: _chipKeys.putIfAbsent(
                                  entry.exercise.exerciseId, GlobalKey.new),
                              label: entry.exercise.name,
                              visible: entry.landed,
                              onRemove: () => _remove(entry),
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        FadeTransition(
          opacity: intro,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.35), end: Offset.zero)
                .animate(intro),
            child: _buildField(width),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Outside the intro fade: focus doesn't change between steps, so
        // the line stays put while the text swaps above it.
        FocusUnderline(animation: _underline),
        Expanded(child: picking ? _buildResults() : const SizedBox.shrink()),
      ],
    );
  }

  Widget _buildField(double width) {
    final picking = _stage == _Stage.exercises;
    final hint = switch (_stage) {
      _Stage.name => _presetName,
      _Stage.dayTitle => _presetDay(_day),
      _ => 'Search exercises',
    };
    if (picking) return _textField(AppTypography.headlineSm, hint, picking);
    // Re-fit on every keystroke. Applied directly rather than tweened - an
    // in-between size is larger than the fit and would wrap for a frame.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _input,
      builder: (context, value, _) {
        final size =
            fitHeroSize(context, value.text.isEmpty ? hint : value.text, width);
        _heroSize = size;
        return _textField(heroStyle(size), hint, picking);
      },
    );
  }

  Widget _textField(TextStyle style, String hint, bool picking) {
    return TextField(
      controller: _input,
      focusNode: _focus,
      autofocus: true,
      // Titles wrap (once they're down at min size); search stays one line.
      // An explicit text keyboard keeps the action key submitting.
      minLines: 1,
      maxLines: picking ? 1 : null,
      keyboardType: TextInputType.text,
      style: style,
      cursorColor: AppColors.accent,
      textCapitalization:
          picking ? TextCapitalization.none : TextCapitalization.words,
      textInputAction: picking ? TextInputAction.done : TextInputAction.next,
      decoration: inkDecoration(hint, style),
      onChanged: _onChanged,
      onSubmitted: (_) => _submit(),
      // Swallow the default unfocus so the keyboard stays up between steps.
      onEditingComplete: () {},
    );
  }

  Widget _buildResults() {
    final items = _visible;
    final query = _input.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xs),
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
            child: Text(
              'SUGGESTED',
              style: AppTypography.labelCaps,
            ),
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
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
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

  Widget _buildBottomBar() {
    final Widget bar = switch (_stage) {
      _Stage.name => PrimaryPillButton(
          key: const ValueKey('bar-name'),
          label: 'Continue',
          icon: Icons.arrow_forward_rounded,
          onPressed: _commitName,
        ),
      _Stage.dayTitle => Row(
          key: ValueKey('bar-day-$_day'),
          children: [
            Expanded(
              child: SecondaryPillButton(
                label: 'Rest day',
                icon: Icons.bedtime_outlined,
                onPressed: () => _commitDay(rest: true),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: PrimaryPillButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => _commitDay(rest: false),
              ),
            ),
          ],
        ),
      _ => PrimaryPillButton(
          key: ValueKey('bar-exercises-$_day'),
          label: _day < _kDurationDays ? 'Next day' : 'Finish',
          icon: _day < _kDurationDays
              ? Icons.arrow_forward_rounded
              : Icons.check_rounded,
          onPressed: _nextDay,
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile, AppSpacing.xs,
          AppSpacing.marginMobile, AppSpacing.md),
      child: AnimatedSwitcher(
        duration: kInkQuick,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        child: bar,
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Stack(
      key: const ValueKey('success'),
      fit: StackFit.expand,
      children: [
        SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 56, color: AppColors.accent),
                const SizedBox(height: AppSpacing.lg),
                Text('${_splitName ?? 'Your split'} is ready',
                    style: AppTypography.headlineLg,
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Every day is built out and ready to go.',
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryPillButton(
                  label: 'Done',
                  icon: Icons.check_rounded,
                  isLoading: _finishing,
                  onPressed: _done,
                ),
              ],
            ),
          ),
        ),
        IgnorePointer(
          child: Lottie.asset(
            'assets/lottie_animations/confetti.json',
            fit: BoxFit.cover,
            repeat: false,
          ),
        ),
      ],
    );
  }
}

/// Seven segments - filled for finished days (dimmer for rest days), tinted
/// for the day being built.
class _DayProgress extends StatelessWidget {
  final Map<int, bool> completed;
  final int? current;

  const _DayProgress({required this.completed, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var day = 1; day <= _kDurationDays; day++)
          Expanded(
            child: AnimatedContainer(
              duration: kInkMorph,
              curve: Curves.easeOutCubic,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.full),
                color: switch (completed[day]) {
                  true => AppColors.accent.withOpacity(0.4),
                  false => AppColors.accent,
                  null => day == current
                      ? AppColors.accent.withOpacity(0.25)
                      : AppColors.outlineVariant.withOpacity(0.4),
                },
              ),
            ),
          ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/live_workout/live_workout_notifier.dart';
import '../../core/live_workout/live_workout_snapshot.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/mascot/mascot_dialog.dart';
import '../../core/widgets/mascot/mascot_pose.dart';
import '../../core/widgets/silen_button.dart';
import '../exercises/exercise_picker_sheet.dart';
import '../exercises/exercise_video_sheet.dart';
import '../exercises/exercises_models.dart';
import '../notifications/notifications_repository.dart';
import '../settings/settings_controller.dart';
import 'active_workout_draft_store.dart';
import 'exercise_memory_store.dart';
import 'today_controller.dart';
import 'today_models.dart';

/// Exercises tagged with this `EquipmentType` (see the seed data in
/// `database/seed/001_SeedReferenceData.sql`) are the only ones where a
/// bar-plus-plates breakdown, or a floor at the empty-bar weight, means
/// anything - every other equipment type (dumbbell, cable, machine,
/// bodyweight, kettlebell) is loaded a different way and would show
/// nonsense plate math if this gate weren't here (e.g. a 30kg dumbbell
/// press incorrectly rendered as "5kg per side" barbell plates).
const _barbellEquipment = 'Barbell';

/// [weightKg] on a dumbbell exercise is the load in *each* hand, not the
/// total moved - so unlike every other equipment type, tonnage for a
/// dumbbell set has to count that load twice. Kettlebell is deliberately
/// excluded: the seeded "Kettlebell Swing" is one two-handed implement,
/// not a pair, so its logged weight is already the total load.
const _bilateralDumbbellEquipment = 'Dumbbell';

/// One set's local draft state. Every *completed* set is flattened and sent
/// to the server alongside the session aggregate in
/// [TodayController.completeWorkout] (see [_finishWorkout]), landing in
/// `dbo.WorkoutSetLogs` - the source of truth the Progress screen's Personal
/// Records card is built from. The set table itself is also kept alive
/// across app kills/backgrounding by mirroring it into an
/// [ActiveWorkoutDraft] on every change (see `_saveDraft`), but that mirror
/// is on-device only, purely to resume this screen - it's a separate copy
/// from the one that gets sent to the backend on finish.
///
/// [weightKg] is always the source of truth in kilograms, regardless of
/// [UserSettings.weightUnit] - the unit only ever affects display/step
/// size, never storage, matching the convention already set by
/// `onboarding_controller.dart`'s weight picker.
class _SetDraft {
  double weightKg;
  int reps;
  bool completed = false;

  _SetDraft({required this.weightKg, required this.reps});
}

const _plateSizesKg = [20.0, 15.0, 10.0, 5.0, 2.5, 1.25];
const _plateSizesLb = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5];

/// kg -> lb, matching the factor already used by
/// `onboarding_flow_screen.dart`'s `_formatWeight`.
const _kgToLb = 2.20462;

/// Greedy per-side plate breakdown for [totalWeightKg] on a [barbellKg]
/// bar, expressed in whichever [unit] the caller wants the plates named in
/// ('kg' or 'lb') - both the target and the bar are converted to that unit
/// first, so a lb-preference lifter sees real lb plate sizes rather than a
/// kg breakdown with a unit label slapped on. Returns an empty list if the
/// target is at or below the bar itself.
List<double> _plateBreakdown(
    double totalWeightKg, double barbellKg, String unit) {
  final isLb = unit == 'lb';
  final total = isLb ? totalWeightKg * _kgToLb : totalWeightKg;
  final bar = isLb ? barbellKg * _kgToLb : barbellKg;
  var perSide = (total - bar) / 2;
  if (perSide <= 0.01) return const [];
  final plates = <double>[];
  for (final plate in (isLb ? _plateSizesLb : _plateSizesKg)) {
    while (perSide + 0.01 >= plate) {
      plates.add(plate);
      perSide -= plate;
    }
  }
  return plates;
}

String _formatWeight(double kg, String unit) {
  final display = unit == 'lb' ? kg * _kgToLb : kg;
  return display.toStringAsFixed(display % 1 == 0 ? 0 : 1);
}

/// Rich, client-side-only set-logging UI seeded from the day's prescribed
/// [TargetExercise]s. Telemetry bar (elapsed timer + rest-timer ring),
/// session/exercise round-progress tracking, an optional exercise demo
/// video, editable set rows with unit-aware plate math, and a bottom action
/// row that walks exercise-by-exercise before submitting the whole
/// session's aggregate via [TodayController.completeWorkout].
class ActiveWorkoutTrackerScreen extends StatefulWidget {
  final TodaySession session;
  final List<TargetExercise> exercises;
  final TodayController controller;

  const ActiveWorkoutTrackerScreen({
    super.key,
    required this.session,
    required this.exercises,
    required this.controller,
  });

  @override
  State<ActiveWorkoutTrackerScreen> createState() =>
      _ActiveWorkoutTrackerScreenState();
}

class _ActiveWorkoutTrackerScreenState extends State<ActiveWorkoutTrackerScreen>
    with WidgetsBindingObserver {
  late List<List<_SetDraft>> _setsByExercise;
  // Session-local only - swapping/adding an exercise here never mutates the
  // underlying split day (see `_swapExercise`/`_addExercise`). Seeded from
  // `widget.exercises` in `_init`, same as `_setsByExercise`, and restored
  // from `ActiveWorkoutDraft.exercises` on resume rather than always
  // re-deriving from `widget.exercises`, so a swap survives an app kill.
  late List<TargetExercise> _exercises;
  int _exerciseIndex = 0;

  // Resolved once from Settings at mount - see the class doc on _SetDraft.
  // Falls back to the spec defaults if Settings hasn't finished its own
  // first load yet (e.g. a very fast cold-start tap-through).
  late final String _weightUnit;
  late final double _barbellStandardKg;

  // Wall-clock rather than a `Stopwatch` - a `Stopwatch` lives only in this
  // object's memory, so it can't tell a resumed screen how much time has
  // actually passed. [_startedAtUtc] is the one thing carried over from a
  // restored `ActiveWorkoutDraft` (see [_init]); `_elapsed` is recomputed
  // from it on every tick instead of tracked incrementally.
  late DateTime _startedAtUtc;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  // False until [_init]'s draft lookup resolves - a single fast local
  // storage read, but still async, so the set table can't be built
  // synchronously in `initState` the way it used to be.
  bool _ready = false;

  bool _isFinishing = false;

  // Guards [_reconcileLoggedSets] against overlapping drains - the ticker and
  // a lifecycle resume can both fire while a platform-channel round-trip is in
  // flight, and replaying the same taps twice would double-log sets. Callers
  // get the in-flight future rather than a no-op, so awaiting a drain (e.g.
  // before finishing) always waits for the tap that triggered it.
  Future<void>? _reconcileInFlight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
  }

  /// A tap made with the app backgrounded has no ticker running to catch it,
  /// so the resume transition is also a drain point.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconcileLoggedSets());
    }
  }

  /// Replays any "Log set" taps the native live surface recorded that haven't
  /// been turned into real sets yet - see
  /// [LiveWorkoutNotifier.drainLoggedSets]. The surface refreshes itself
  /// instantly when tapped; this is what persists the corresponding set into
  /// the workout draft.
  ///
  /// Called on resume (a tap made with the app backgrounded), on every ticker
  /// tick (a tap made while the app is open but the surface is what the user
  /// is looking at), and once at the end of [_init] (a tap made while the app
  /// was fully killed and is only now cold-starting back into this session).
  Future<void> _reconcileLoggedSets() {
    final inFlight = _reconcileInFlight;
    if (inFlight != null) return inFlight;
    final tracked =
        _drainLoggedSets().whenComplete(() => _reconcileInFlight = null);
    _reconcileInFlight = tracked;
    return tracked;
  }

  Future<void> _drainLoggedSets() async {
    if (!_ready) return;
    final sessionId = widget.session.workoutSessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    final pending =
        await LiveWorkoutNotifier.instance.drainLoggedSets(sessionId);
    if (!mounted) return;
    // Replay against whatever is still the active set at drain time - bounded
    // by _activeSetIndex rather than blindly looping `pending` times, so a
    // stray extra tap can never log past the last real set.
    for (var i = 0; i < pending; i++) {
      final active = _activeSetIndex;
      if (active == null) break;
      _logSet(active);
    }
  }

  /// Seeds the set table from the day's prescribed exercises, then checks
  /// for a still-fresh [ActiveWorkoutDraft] for this exact session and, if
  /// one exists, restores its sets/exercise index/start time over the fresh
  /// seed instead - see [ActiveWorkoutDraftStore] for the freshness window.
  Future<void> _init() async {
    final settings = context.read<SettingsController>().state.data;
    _weightUnit = settings?.weightUnit ?? 'kg';
    _barbellStandardKg = settings?.barbellStandardKg ?? 20.0;

    // Last time each exercise was actually logged, if ever - a fresh set
    // starts from there instead of always resetting to the barbell standard
    // or the target rep-range midpoint, matching how a lifter actually
    // plans a set ("what did I do last time").
    final memory = await ExerciseMemoryStore.instance.loadAll();

    final freshSets = widget.exercises.map((exercise) {
      final remembered = memory[exercise.exerciseId];
      return List.generate(
        exercise.targetSets <= 0 ? 1 : exercise.targetSets,
        (_) => _SetDraft(
          weightKg:
              remembered?.weightKg ?? _weightFloorKgFor(exercise.equipmentType),
          reps: remembered?.reps ??
              ((exercise.targetRepsLow + exercise.targetRepsHigh) / 2)
                  .round()
                  .clamp(1, 999),
        ),
      );
    }).toList();

    final sessionId = widget.session.workoutSessionId;
    final draft = sessionId == null
        ? null
        : await ActiveWorkoutDraftStore.instance.load(sessionId);

    // Only trusted when it matches the shape of today's exercises - a
    // draft saved against a different/older plan for the same session id
    // would otherwise restore the wrong number of exercises or sets. Also
    // requires a matching `exercises` list (absent/short on a draft saved
    // before the swap/add feature, or one saved before any swap happened),
    // so a stale-format draft falls back to the fresh plan rather than
    // resuming with mismatched exercise data.
    final draftMatchesShape = draft != null &&
        draft.setsByExercise.length == freshSets.length &&
        draft.exercises.length == freshSets.length &&
        draft.exerciseIndex >= 0 &&
        draft.exerciseIndex < freshSets.length;

    if (!mounted) return;
    setState(() {
      _setsByExercise = draftMatchesShape
          ? draft.setsByExercise
              .map((sets) => sets
                  .map((s) => _SetDraft(weightKg: s.weightKg, reps: s.reps)
                    ..completed = s.completed)
                  .toList())
              .toList()
          : freshSets;
      _exercises = draftMatchesShape
          ? List.of(draft.exercises)
          : List.of(widget.exercises);
      _exerciseIndex = draftMatchesShape ? draft.exerciseIndex : 0;
      _startedAtUtc =
          draftMatchesShape ? draft.startedAtUtc : DateTime.now().toUtc();
      _elapsed = DateTime.now().toUtc().difference(_startedAtUtc);
      _ready = true;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(
          () => _elapsed = DateTime.now().toUtc().difference(_startedAtUtc));
      // A "Log set" tap on the native surface while the app itself is open
      // has no lifecycle transition to piggyback on, so the ticker is also
      // the poll that turns those taps into logged sets. Cheap when there is
      // nothing pending (one channel call that returns 0).
      unawaited(_reconcileLoggedSets());
    });
    // Persist immediately so Home can offer "Continue Workout" as soon as
    // this screen has been opened once, even before a set is logged - the
    // elapsed timer is already running by then.
    _saveDraft();
    // Surface the session on the Lock Screen / Dynamic Island / Android
    // notification tray for the whole time it's in progress. The elapsed
    // clock is computed natively from `_startedAtUtc`, so this only needs to
    // fire on state changes, not on every ticker tick.
    unawaited(LiveWorkoutNotifier.instance.start(_liveSnapshot));
    // Cold-start case: a "Log set" tap landed while the app was fully killed
    // (not just backgrounded), so there's no resume transition to catch it -
    // this screen re-opening from the restored draft is the only signal.
    unawaited(_reconcileLoggedSets());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  /// Fire-and-forget snapshot of the current sets/exercise/start-time to
  /// device storage, so the workout survives the app being backgrounded or
  /// killed. A no-op when the session has no id (nothing meaningful to key
  /// the draft on) - same guard `_finishWorkout` already uses.
  ///
  /// The heartbeat is throttled separately from the local draft save: saving is
  /// cheap and must happen on every change, but the server ping only needs to
  /// mean "still active". Without this, every weight/rep stepper tap issued its
  /// own `POST /notifications/workout-heartbeat`.
  static const _heartbeatMinGap = Duration(seconds: 10);
  DateTime? _lastHeartbeatUtc;

  void _saveDraft() {
    final sessionId = widget.session.workoutSessionId;
    if (sessionId == null) return;
    final now = DateTime.now();
    if (_lastHeartbeatUtc == null ||
        now.difference(_lastHeartbeatUtc!) >= _heartbeatMinGap) {
      _lastHeartbeatUtc = now;
      unawaited(_sendWorkoutHeartbeat(sessionId));
    }
    unawaited(ActiveWorkoutDraftStore.instance.save(ActiveWorkoutDraft(
      workoutSessionId: sessionId,
      exerciseIndex: _exerciseIndex,
      setsByExercise: _setsByExercise
          .map((sets) => sets
              .map((s) => DraftSet(
                    weightKg: s.weightKg,
                    reps: s.reps,
                    completed: s.completed,
                  ))
              .toList())
          .toList(),
      exercises: _exercises,
      startedAtUtc: _startedAtUtc,
      savedAtUtc: DateTime.now().toUtc(),
    )));
  }

  /// Fire-and-forget "still in the gym" ping. Fires whenever the draft is
  /// saved (screen open, set logged, exercise advanced), which is exactly the
  /// activity signal the server needs to time a set-logging nudge around real
  /// idle gaps. Best-effort; a failure never affects the workout.
  Future<void> _sendWorkoutHeartbeat(String sessionId) async {
    try {
      await context
          .read<NotificationsRepository>()
          .sendWorkoutHeartbeat(workoutSessionId: sessionId);
    } catch (_) {
      // Intentionally swallowed.
    }
  }

  List<_SetDraft> get _currentSets => _setsByExercise[_exerciseIndex];
  TargetExercise get _currentExercise => _exercises[_exerciseIndex];
  bool get _isLastExercise => _exerciseIndex == _exercises.length - 1;

  /// Current session state in the shape the native live surfaces expect (see
  /// [LiveWorkoutNotifier]). Built fresh on every read so it always mirrors
  /// whatever `_setsByExercise`/`_exerciseIndex` are at the moment a set is
  /// logged or the exercise advances.
  LiveWorkoutSnapshot get _liveSnapshot => LiveWorkoutSnapshot(
        sessionId: widget.session.workoutSessionId ?? '',
        exerciseName: _currentExercise.name,
        exerciseNumber: _exerciseIndex + 1,
        exerciseCount: _exercises.length,
        completedSets: _completedSetsInCurrentExercise,
        totalSets: _currentSets.length,
        startedAtUtc: _startedAtUtc,
      );

  /// Fire-and-forget push of the current snapshot into an already-visible live
  /// surface - a no-op when the platform has none, or when the OS dropped it.
  void _syncLiveWorkout() {
    unawaited(LiveWorkoutNotifier.instance.update(_liveSnapshot));
  }

  /// kg per tap: a quarter-plate-per-side jump in whichever unit is active
  /// (2.5 kg, or 5 lb converted back to kg for storage) rather than a fixed
  /// kg step that would look like an odd fractional lb jump to an
  /// lb-preference lifter.
  double get _weightStepKg => _weightUnit == 'lb' ? 5 / _kgToLb : 2.5;

  /// The lowest weight this exercise's equipment can plausibly show. Only a
  /// barbell exercise (or one with no `equipmentType` on record, so the
  /// pre-existing behaviour holds rather than guessing) has a real hard
  /// floor - the empty bar itself. Every other equipment type just floors
  /// at one weight-step above zero, so a dumbbell/cable/machine set can be
  /// dialled down without getting stuck at a 20kg barbell-bar minimum that
  /// has nothing to do with what's actually in the lifter's hands.
  double _weightFloorKgFor(String? equipmentType) =>
      (equipmentType == null || equipmentType == _barbellEquipment)
          ? _barbellStandardKg
          : _weightStepKg;

  double get _weightFloorKg =>
      _weightFloorKgFor(_currentExercise.equipmentType);

  /// The current exercise's first not-yet-logged set - the only set this
  /// screen ever shows. `null` once every set is logged (see
  /// `_ExerciseCompleteCard`).
  int? get _activeSetIndex {
    final i = _currentSets.indexWhere((s) => !s.completed);
    return i == -1 ? null : i;
  }

  /// How many sets in the current exercise are logged, for the header ring.
  /// `_logSet` only ever completes `_activeSetIndex` (the first incomplete
  /// set), so completion is always contiguous from the front - the count is
  /// just `_activeSetIndex`, or every set once none are left incomplete.
  int get _completedSetsInCurrentExercise =>
      _activeSetIndex ?? _currentSets.length;

  /// Real target reps only - `TargetExercise` defaults both bounds to 0
  /// when the plan carries no rep prescription, and a "Target 0-0 reps"
  /// readout would read as a bug, not an empty state.
  bool get _hasRealRepTarget =>
      _currentExercise.targetRepsLow > 0 && _currentExercise.targetRepsHigh > 0;

  /// Reps at (or above) which the *previous* completed set in this exercise
  /// is considered to have moved easily enough that the upcoming set should
  /// go up in weight - the prescribed top of the rep range when there is
  /// one, or a flat 12 (per the user's own example) otherwise.
  int get _repsSuggestingHeavier =>
      _hasRealRepTarget ? _currentExercise.targetRepsHigh : 12;

  /// True right as a new set becomes active if the set just before it hit
  /// the rep ceiling above - the minimalist progressive-overload nudge
  /// shown on `_CurrentSetCard` next to the weight stat.
  bool get _suggestWeightIncrease {
    final active = _activeSetIndex;
    if (active == null || active == 0) return false;
    final previous = _currentSets[active - 1];
    return previous.completed && previous.reps >= _repsSuggestingHeavier;
  }

  void _logSet(int index) {
    setState(() {
      _currentSets[index].completed = true;
      // Carry the just-logged weight into the next set - a lifter almost
      // always repeats the same weight set-to-set unless they deliberately
      // adjust it, so the next set should open at what was just lifted
      // rather than resetting to the pre-workout seed from `_init` (which
      // every target set was given the same starting value from, since only
      // the active set is ever editable before its turn comes). Mirrors
      // `_addSet`'s carry-forward for a set added beyond the target count.
      if (index + 1 < _currentSets.length) {
        _currentSets[index + 1].weightKg = _currentSets[index].weightKg;
      }
    });
    _saveDraft();
    _syncLiveWorkout();
    // Fire-and-forget, like `_saveDraft` - remembers this exercise's weight
    // and reps for next time (see `ExerciseMemoryStore`), independent of
    // whether this whole workout ever gets finished.
    unawaited(ExerciseMemoryStore.instance.remember(
      _currentExercise.exerciseId,
      _currentSets[index].weightKg,
      _currentSets[index].reps,
    ));
  }

  void _addSet() {
    final last = _currentSets.isNotEmpty ? _currentSets.last : null;
    setState(() => _currentSets.add(_SetDraft(
          weightKg: last?.weightKg ?? _weightFloorKg,
          reps: last?.reps ?? _currentExercise.targetRepsLow,
        )));
    _saveDraft();
    _syncLiveWorkout();
  }

  /// Drops one set from the current exercise, whether it's still to come or
  /// already logged - the plan's `targetSets` is only ever a starting seed
  /// (see `_init`), so working out one fewer set than prescribed, or
  /// deleting one added by mistake via [_addSet], is just as valid as adding
  /// one. Always leaves at least one set behind: an exercise with zero sets
  /// isn't a smaller version of itself, it's a different exercise skipped
  /// entirely, which isn't what this button is for.
  bool get _canRemoveSet => _currentSets.length > 1;

  void _removeSet(int index) {
    if (!_canRemoveSet) return;
    setState(() => _currentSets.removeAt(index));
    _saveDraft();
    _syncLiveWorkout();
  }

  /// Same seed rule `_init` uses for a fresh set table - last-logged
  /// weight/reps for this exercise if there's any memory of it, otherwise
  /// the equipment floor and the rep-range midpoint - reused so a swapped
  /// or newly-added exercise opens exactly like it would have if the day
  /// had been planned with it from the start.
  List<_SetDraft> _seedSets(
    ExerciseSummary exercise,
    int targetSets,
    int repsLow,
    int repsHigh,
    Map<String, ExerciseMemory> memory,
  ) {
    final remembered = memory[exercise.exerciseId];
    return List.generate(
      targetSets <= 0 ? 1 : targetSets,
      (_) => _SetDraft(
        weightKg:
            remembered?.weightKg ?? _weightFloorKgFor(exercise.equipmentType),
        reps: remembered?.reps ??
            ((repsLow + repsHigh) / 2).round().clamp(1, 999),
      ),
    );
  }

  TargetExercise _toTargetExercise(ExerciseSummary exercise, int targetSets,
          int repsLow, int repsHigh) =>
      TargetExercise(
        exerciseId: exercise.exerciseId,
        name: exercise.name,
        muscleGroup: exercise.muscleGroup,
        equipmentType: exercise.equipmentType,
        demoVideoUrl: exercise.demoVideoUrl,
        targetSets: targetSets,
        targetRepsLow: repsLow,
        targetRepsHigh: repsHigh,
      );

  /// Replaces the current exercise for the rest of *this* session only -
  /// never mutates the split day it came from. Keeps the outgoing
  /// exercise's own target sets/rep-range (a like-for-like substitution:
  /// same volume, different movement) but reseeds the set table's
  /// weight/reps from the new exercise's own memory rather than carrying
  /// over the outgoing exercise's numbers, which would be meaningless for a
  /// different lift.
  Future<void> _swapExercise() async {
    final picked =
        await showExercisePickerSheet(context, title: 'Swap exercise');
    if (picked == null || !mounted) return;
    final memory = await ExerciseMemoryStore.instance.loadAll();
    if (!mounted) return;
    final outgoing = _currentExercise;
    setState(() {
      _exercises[_exerciseIndex] = _toTargetExercise(picked,
          outgoing.targetSets, outgoing.targetRepsLow, outgoing.targetRepsHigh);
      _setsByExercise[_exerciseIndex] = _seedSets(picked, outgoing.targetSets,
          outgoing.targetRepsLow, outgoing.targetRepsHigh, memory);
    });
    _saveDraft();
    _syncLiveWorkout();
  }

  /// Appends a brand-new exercise (and an empty-ish, one-set starting slot)
  /// to the end of this session - session-local only, same as
  /// [_swapExercise]. No prescribed rep range exists for an ad hoc addition,
  /// so both bounds are left at 0 (see `_hasRealRepTarget`) rather than
  /// inventing one.
  Future<void> _addExercise() async {
    final picked =
        await showExercisePickerSheet(context, title: 'Add exercise');
    if (picked == null || !mounted) return;
    final memory = await ExerciseMemoryStore.instance.loadAll();
    if (!mounted) return;
    setState(() {
      _exercises.add(_toTargetExercise(picked, 1, 0, 0));
      _setsByExercise.add(_seedSets(picked, 1, 0, 0, memory));
    });
    _saveDraft();
    _syncLiveWorkout();
  }

  void _adjustWeight(int index, double directionSign) {
    setState(() {
      final floor = _weightFloorKg;
      final next = _currentSets[index].weightKg + directionSign * _weightStepKg;
      _currentSets[index].weightKg =
          next < floor ? floor : double.parse(next.toStringAsFixed(2));
    });
    _saveDraft();
  }

  void _setWeightDirect(int index, double kg) {
    final floor = _weightFloorKg;
    setState(() => _currentSets[index].weightKg = kg < floor ? floor : kg);
    _saveDraft();
  }

  void _adjustReps(int index, int delta) {
    setState(() {
      final next = _currentSets[index].reps + delta;
      _currentSets[index].reps = next < 1 ? 1 : next;
    });
    _saveDraft();
  }

  void _setRepsDirect(int index, int reps) {
    setState(() => _currentSets[index].reps = reps < 1 ? 1 : reps);
    _saveDraft();
  }

  double get _totalTonnageKg {
    var total = 0.0;
    for (var i = 0; i < _setsByExercise.length; i++) {
      // See `_bilateralDumbbellEquipment` - a dumbbell set's logged weight
      // is per hand, so the load actually moved is double what a
      // barbell/machine/cable set of the same number would be.
      final perRepMultiplier =
          _exercises[i].equipmentType == _bilateralDumbbellEquipment ? 2 : 1;
      for (final set in _setsByExercise[i]) {
        if (set.completed) {
          total += set.weightKg * set.reps * perRepMultiplier;
        }
      }
    }
    return total;
  }

  /// Flattens every *completed* set across all exercises into the wire
  /// shape the backend's `usp_WorkoutSession_Complete` expects, so real PRs
  /// can be computed server-side (see `dbo.WorkoutSetLogs`). Set numbers are
  /// 1-based and, unlike [_totalTonnageKg], the weight here is never doubled
  /// for a bilateral dumbbell set - a raw log records what was actually on
  /// each dumbbell, since the doubling is a display/aggregate concern, not
  /// how the lift itself is logged.
  List<SetLogEntry> get _completedSetLogs {
    final logs = <SetLogEntry>[];
    for (var i = 0; i < _setsByExercise.length; i++) {
      final exerciseId = _exercises[i].exerciseId;
      var setNumber = 0;
      for (final set in _setsByExercise[i]) {
        setNumber++;
        if (!set.completed) continue;
        logs.add(SetLogEntry(
          exerciseId: exerciseId,
          setNumber: setNumber,
          weightKg: set.weightKg,
          reps: set.reps,
        ));
      }
    }
    return logs;
  }

  Future<void> _onPrimaryAction() async {
    if (!_isLastExercise) {
      setState(() => _exerciseIndex++);
      _saveDraft();
      _syncLiveWorkout();
      return;
    }
    await _finishWorkout();
  }

  Future<void> _finishWorkout() async {
    final sessionId = widget.session.workoutSessionId;
    if (sessionId == null) {
      unawaited(LiveWorkoutNotifier.instance.stop());
      Navigator.of(context).pop();
      return;
    }
    // Fold in any surface taps that haven't been replayed yet before
    // snapshotting the completed sets below - otherwise a set logged from the
    // Lock Screen in the last second would be dropped from the submission.
    // Drained twice so a tap that lands while the first drain is in flight is
    // still picked up; the second pass is a cheap no-op when nothing is left.
    await _reconcileLoggedSets();
    await _reconcileLoggedSets();
    if (!mounted) return;
    setState(() => _isFinishing = true);
    final durationMinutes = _elapsed.inMinutes < 1 ? 1 : _elapsed.inMinutes;
    final ok = await widget.controller.completeWorkout(
      workoutSessionId: sessionId,
      durationMinutes: durationMinutes,
      tonnageKg: _totalTonnageKg > 0 ? _totalTonnageKg : null,
      setLogs: _completedSetLogs,
    );
    if (!mounted) return;
    setState(() => _isFinishing = false);
    if (ok) {
      // Session is logged server-side now - the local draft would only ever
      // be stale from here on, so it's cleared regardless of whether the
      // mascot dialog below is dismissed or the screen is popped first.
      // Fire-and-forget (like `_saveDraft`) rather than awaited: nothing
      // below depends on the clear having finished, and awaiting it would
      // just be one more async gap to guard `context` against.
      unawaited(ActiveWorkoutDraftStore.instance.clear());
      // Session is logged - the live surface has nothing left to track.
      unawaited(LiveWorkoutNotifier.instance.stop());
      // Streak-milestone heuristic: no per-set PR-detection data exists
      // server-side, so a "proud" moment is approximated client-side as
      // hitting a 7-day streak multiple; every other finish is "celebrating".
      final streakDays = widget.controller.state.data?.currentStreakDays ?? 0;
      final isMilestone = streakDays > 0 && streakDays % 7 == 0;
      await MascotDialog.show(
        context,
        pose: isMilestone ? MascotPose.proud : MascotPose.celebrating,
        title: isMilestone ? '$streakDays-day streak!' : 'Workout complete',
        message: isMilestone
            ? 'You\'re on fire - $streakDays days in a row. Keep it going.'
            : 'Nice work. Your session has been logged.',
        actionLabel: 'Nice',
        showConfetti: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } else if (widget.controller.actionError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.actionError!)));
    }
  }

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Text('Leave workout?', style: AppTypography.headlineSm),
        content: Text(
            'Your progress is saved - pick up from here with Continue Workout on Home.',
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Keep training', style: AppTypography.bodyMd)),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('Leave', style: AppTypography.bodyMd)),
        ],
      ),
    );
    if (leave != true) return;
    // Deliberately no draft clear here (unlike `_finishWorkout`) - leaving
    // is a pause, not an abandon, and the dialog above now promises the
    // sets already logged are exactly what "Continue Workout" on Home will
    // hand back. `_saveDraft` has already been keeping this current after
    // every set/weight/rep change, so there's nothing left to persist here.
    // Stop before popping instead of relying solely on dispose: this gives
    // the platform channel time to receive the command while the Flutter
    // engine and route are definitely still alive.
    await LiveWorkoutNotifier.instance.stop();
    if (mounted) Navigator.of(context).pop();
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      // Draft lookup (see `_init`) hasn't resolved yet - a single fast
      // local read, so this shows for at most a frame or two, never long
      // enough to warrant its own skeleton/shimmer state.
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: AppColors.accent),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Subtle in-progress-workout flourish - a low-opacity mascot accent
          // tucked in the corner, purely decorative.
          Positioned(
            right: -18,
            bottom: 96,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.08,
                child: Image.asset(MascotPose.lifting.assetPath, width: 160),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                      AppSpacing.sm, AppSpacing.marginMobile, 0),
                  child: _TelemetryBar(
                    onClose: _confirmExit,
                    elapsedLabel: _formatElapsed(_elapsed),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.marginMobile),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                                  begin: const Offset(0.04, 0),
                                  end: Offset.zero)
                              .animate(animation),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey(_exerciseIndex),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                    'EXERCISE ${_exerciseIndex + 1} OF ${_exercises.length}',
                                    style: AppTypography.labelCaps
                                        .copyWith(color: AppColors.accent)),
                              ),
                              if (_currentExercise.demoVideoUrl != null) ...[
                                _WatchDemoChip(
                                  isVideo: isVideoUrl(
                                      _currentExercise.demoVideoUrl!),
                                  onTap: () => showExerciseVideoSheet(
                                    context,
                                    url: _currentExercise.demoVideoUrl!,
                                    exerciseName: _currentExercise.name,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xxs),
                              ],
                              _ExerciseMenuChip(
                                onSwap: _swapExercise,
                                onAdd: _addExercise,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // The exercise name as the screen's title - the
                              // largest, first thing read on the page, same
                              // headline weight Home gives its own title.
                              Expanded(
                                child: Text(_currentExercise.name,
                                    style: AppTypography.headlineLg
                                        .copyWith(fontSize: 32)),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              // One gapped ring segment per set, sweeping
                              // smoothly to full whenever `_logSet` completes
                              // one - a glanceable "how far into this exercise
                              // am I" that doesn't need its own progress bar.
                              _SetProgressRing(
                                totalSets: _currentSets.length,
                                completedSets: _completedSetsInCurrentExercise,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            // The set count in the target is the *live* count
                            // (grows with Add Set), not the plan's static
                            // targetSets - and the whole target only shows up
                            // when the plan actually prescribed a rep range.
                            _hasRealRepTarget
                                ? '${_currentExercise.muscleGroup} · Target ${_currentSets.length} × ${_currentExercise.targetRepsLow}-${_currentExercise.targetRepsHigh} reps'
                                : _currentExercise.muscleGroup,
                            style: AppTypography.bodyMd
                                .copyWith(color: AppColors.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpacing.xxxl),
                          // Only the current set - no list of upcoming or past
                          // sets to scan past. Keyed on the active set (or the
                          // "all done" state) so logging a set, or adding a new
                          // one once the exercise was fully logged, animates
                          // forward instead of just swapping numbers in place.
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.96, end: 1)
                                    .animate(animation),
                                child: child,
                              ),
                            ),
                            child: _activeSetIndex != null
                                ? _CurrentSetCard(
                                    key: ValueKey('set-$_activeSetIndex'),
                                    setIndex: _activeSetIndex!,
                                    totalSets: _currentSets.length,
                                    set: _currentSets[_activeSetIndex!],
                                    weightUnit: _weightUnit,
                                    barbellStandardKg: _barbellStandardKg,
                                    weightFloorKg: _weightFloorKg,
                                    isBarbell: _currentExercise.equipmentType ==
                                            _barbellEquipment ||
                                        _currentExercise.equipmentType == null,
                                    suggestWeightIncrease:
                                        _suggestWeightIncrease,
                                    canRemove: _canRemoveSet,
                                    onLog: () => _logSet(_activeSetIndex!),
                                    onRemove: () =>
                                        _removeSet(_activeSetIndex!),
                                    onWeightDelta: (sign) =>
                                        _adjustWeight(_activeSetIndex!, sign),
                                    onRepsDelta: (delta) =>
                                        _adjustReps(_activeSetIndex!, delta),
                                    onWeightDirectKg: (kg) =>
                                        _setWeightDirect(_activeSetIndex!, kg),
                                    onRepsDirect: (reps) =>
                                        _setRepsDirect(_activeSetIndex!, reps),
                                  )
                                : _ExerciseCompleteCard(
                                    key: const ValueKey('complete'),
                                    totalSets: _currentSets.length,
                                    canRemoveSet: _canRemoveSet,
                                    onRemoveLastSet: () =>
                                        _removeSet(_currentSets.length - 1),
                                  ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                      AppSpacing.sm, AppSpacing.marginMobile, AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: SecondaryPillButton(
                            label: 'Add Set', onPressed: _addSet),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: PrimaryPillButton(
                          label: _isLastExercise
                              ? 'Finish Workout'
                              : 'Finish Exercise',
                          icon: _isLastExercise
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          isLoading: _isFinishing,
                          onPressed: _onPrimaryAction,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TelemetryBar extends StatelessWidget {
  final VoidCallback onClose;
  final String elapsedLabel;

  const _TelemetryBar({
    required this.onClose,
    required this.elapsedLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onClose,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 40,
            height: 40,
            child:
                Icon(Icons.close_rounded, size: 20, color: AppColors.onSurface),
          ),
        ),
        const Spacer(),
        Icon(Icons.timer_outlined, size: 16, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(elapsedLabel,
            style:
                AppTypography.numericUnit.copyWith(color: AppColors.onSurface)),
        const Spacer(),
        // Balances the close button's width so the elapsed time stays
        // visually centered now that nothing sits to its right.
        const SizedBox(width: 40),
      ],
    );
  }
}

/// Compact icon-only chip opening a bottom sheet with "Swap exercise" /
/// "Add exercise" - the entry point for the session-local exercise
/// swap/add feature (see `_swapExercise`/`_addExercise`). A plain circular
/// icon rather than another labeled pill like [_WatchDemoChip], since it's
/// always present (unlike the demo chip, which only shows up when the
/// exercise has a reference video) and doesn't need to compete for width in
/// the header row.
class _ExerciseMenuChip extends StatelessWidget {
  final VoidCallback onSwap;
  final VoidCallback onAdd;

  const _ExerciseMenuChip({required this.onSwap, required this.onAdd});

  Future<void> _openSheet(BuildContext context) async {
    final action = await showModalBottomSheet<VoidCallback>(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(Icons.swap_horiz_rounded, color: AppColors.onSurface),
              title: Text('Swap this exercise', style: AppTypography.bodyMd),
              subtitle: Text('Replace it for this workout only',
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.onSurfaceVariant)),
              onTap: () => Navigator.of(sheetContext).pop(onSwap),
            ),
            ListTile(
              leading: Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.onSurface),
              title: Text('Add an exercise', style: AppTypography.bodyMd),
              subtitle: Text('Tack on something extra for today',
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.onSurfaceVariant)),
              onTap: () => Navigator.of(sheetContext).pop(onAdd),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openSheet(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.more_horiz_rounded,
            size: 16, color: AppColors.onSurface),
      ),
    );
  }
}

class _WatchDemoChip extends StatelessWidget {
  final bool isVideo;
  final VoidCallback onTap;

  const _WatchDemoChip({required this.isVideo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isVideo ? Icons.play_circle_fill_rounded : Icons.image_rounded,
                size: 16, color: AppColors.accent),
            const SizedBox(width: 4),
            Text(isVideo ? 'Watch form' : 'View form',
                style: AppTypography.labelCaps
                    .copyWith(color: AppColors.onSurface, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

/// A ring split into one gapped segment per set - empty until that set is
/// logged, then sweeps to fully filled. `_logSet` only ever completes
/// `_activeSetIndex` (the first incomplete set), so segments always fill
/// left-to-right in set order - a single fractional "how many segments are
/// filled" value is enough to drive every segment's fill via one implicit
/// tween, rather than tracking each segment's own animation state.
class _SetProgressRing extends StatelessWidget {
  static const _size = 48.0;
  static const _strokeWidth = 5.0;

  final int totalSets;
  final int completedSets;

  const _SetProgressRing(
      {required this.totalSets, required this.completedSets});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: TweenAnimationBuilder<double>(
        // `begin` only matters on the very first build - TweenAnimationBuilder
        // animates from whatever value it's currently at on every later
        // change, same convention as `RadialProgressRing`.
        tween: Tween(begin: 0, end: completedSets.toDouble()),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => CustomPaint(
          painter: _SegmentedRingPainter(
            totalSegments: totalSets < 1 ? 1 : totalSets,
            filledSegments: value,
            strokeWidth: _strokeWidth,
            trackColor: AppColors.surfaceContainerHighest,
            activeColor: AppColors.accent,
          ),
        ),
      ),
    );
  }
}

class _SegmentedRingPainter extends CustomPainter {
  final int totalSegments;
  final double filledSegments;
  final double strokeWidth;
  final Color trackColor;
  final Color activeColor;

  _SegmentedRingPainter({
    required this.totalSegments,
    required this.filledSegments,
    required this.strokeWidth,
    required this.trackColor,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // A fixed angular gap reads as clean dashes at the set counts this
    // screen realistically shows (rarely more than 4-5) - it only starts
    // crowding well past that, which a normal workout won't reach.
    const gap = 0.26; // radians
    final sweep = totalSegments == 1
        ? 2 * math.pi - gap
        : (2 * math.pi - gap * totalSegments) / totalSegments;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    var start = -math.pi / 2;
    for (var i = 0; i < totalSegments; i++) {
      canvas.drawArc(rect, start, sweep, false, trackPaint);
      final localFill = (filledSegments - i).clamp(0.0, 1.0);
      if (localFill > 0) {
        canvas.drawArc(rect, start, sweep * localFill, false, activePaint);
      }
      start += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedRingPainter oldDelegate) =>
      oldDelegate.totalSegments != totalSegments ||
      oldDelegate.filledSegments != filledSegments ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.activeColor != activeColor;
}

/// The single active set for the current exercise - the only set this
/// screen ever shows (see the `_activeSetIndex`-keyed `AnimatedSwitcher` in
/// `ActiveWorkoutTrackerScreen.build`). Large and centered, in the spirit
/// of the onboarding wheel screens' one-focal-value layout, rather than a
/// dense multi-row table of every set at once.
class _CurrentSetCard extends StatelessWidget {
  final int setIndex;
  final int totalSets;
  final _SetDraft set;
  final String weightUnit;
  final double barbellStandardKg;
  final double weightFloorKg;
  // Whether this exercise is a confirmed-or-unknown barbell lift - the only
  // case where a bar-plus-plates breakdown is meaningful (see
  // `_barbellEquipment` on the parent state).
  final bool isBarbell;
  final bool suggestWeightIncrease;
  // False once this is the exercise's only remaining set - see `_canRemoveSet`.
  final bool canRemove;
  final VoidCallback onLog;
  final VoidCallback onRemove;
  final ValueChanged<double> onWeightDelta;
  final ValueChanged<int> onRepsDelta;
  final ValueChanged<double> onWeightDirectKg;
  final ValueChanged<int> onRepsDirect;

  const _CurrentSetCard({
    super.key,
    required this.setIndex,
    required this.totalSets,
    required this.set,
    required this.weightUnit,
    required this.barbellStandardKg,
    required this.weightFloorKg,
    required this.isBarbell,
    required this.suggestWeightIncrease,
    required this.canRemove,
    required this.onLog,
    required this.onRemove,
    required this.onWeightDelta,
    required this.onRepsDelta,
    required this.onWeightDirectKg,
    required this.onRepsDirect,
  });

  Future<void> _editWeight(BuildContext context) async {
    final result = await _showQuickEntrySheet(
      context,
      title: 'Set ${setIndex + 1} weight',
      unitSuffix: weightUnit,
      initialValue: double.parse(_formatWeight(set.weightKg, weightUnit)),
      step: weightUnit == 'lb' ? 5 : 2.5,
      min: weightUnit == 'lb' ? weightFloorKg * _kgToLb : weightFloorKg,
    );
    if (result != null) {
      onWeightDirectKg(weightUnit == 'lb' ? result / _kgToLb : result);
    }
  }

  Future<void> _editReps(BuildContext context) async {
    final result = await _showQuickEntrySheet(
      context,
      title: 'Set ${setIndex + 1} reps',
      unitSuffix: 'reps',
      initialValue: set.reps.toDouble(),
      step: 1,
      min: 1,
      isWholeNumber: true,
    );
    if (result != null) onRepsDirect(result.round());
  }

  @override
  Widget build(BuildContext context) {
    final plates = isBarbell
        ? _plateBreakdown(set.weightKg, barbellStandardKg, weightUnit)
        : const <double>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('SET ${setIndex + 1} OF ',
                    style: AppTypography.labelCaps
                        .copyWith(color: AppColors.onSurfaceVariant)),
                // The one place a set actually being added is visible in this
                // current-set-only layout - the new set itself never appears on
                // screen until it's the active one, so this count pulsing is
                // Add Set's only on-screen feedback.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: Tween<double>(begin: 0.5, end: 1).animate(
                        CurvedAnimation(
                            parent: animation, curve: Curves.easeOutBack)),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Text('$totalSets',
                      key: ValueKey(totalSets),
                      style: AppTypography.labelCaps
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ),
              ],
            ),
            // Pinned to the trailing edge rather than in the centered Row
            // above, so removing the affordance for the last remaining set
            // (see `canRemove`) never shifts the "SET X OF Y" text off
            // center. Hidden rather than disabled in that case - a dead
            // trash icon here would invite exactly the tap it can't honor.
            if (canRemove)
              Positioned(
                right: 0,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onRemove();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    child: Icon(Icons.delete_outline_rounded,
                        size: 18, color: AppColors.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _BigStat(
          value: '${_formatWeight(set.weightKg, weightUnit)} $weightUnit',
          label: 'WEIGHT',
          onMinus: () => onWeightDelta(-1),
          onPlus: () => onWeightDelta(1),
          onTap: () => _editWeight(context),
        ),
        if (plates.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
              'Per side: ${plates.map((p) => p % 1 == 0 ? p.toStringAsFixed(0) : p.toStringAsFixed(2)).join(' + ')} $weightUnit',
              style: AppTypography.labelSm
                  .copyWith(color: AppColors.onSurfaceVariant)),
        ],
        if (suggestWeightIncrease) ...[
          const SizedBox(height: AppSpacing.xs),
          // Minimalist by design: a quiet inline hint, not a dialog or
          // banner - the last set already cleared the rep ceiling, so this
          // is a nudge to go up, not a decision that needs confirming.
          GestureDetector(
            onTap: () => onWeightDelta(1),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.trending_up_rounded,
                      size: 14, color: AppColors.accent),
                  const SizedBox(width: AppSpacing.xxs),
                  Text('Last set was easy - try going heavier',
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.accent)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _BigStat(
          value: '${set.reps} reps',
          label: 'REPS',
          onMinus: () => onRepsDelta(-1),
          onPlus: () => onRepsDelta(1),
          onTap: () => _editReps(context),
        ),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: PrimaryPillButton(
            label: 'Log Set',
            icon: Icons.check_rounded,
            height: 56,
            onPressed: onLog,
          ),
        ),
      ],
    );
  }
}

/// Shown once every set in the exercise is logged, in place of
/// `_CurrentSetCard` - there's no "current set" left to display, just a
/// quiet confirmation until the user adds another set or moves on via the
/// bottom "Finish Exercise"/"Finish Workout" button.
class _ExerciseCompleteCard extends StatelessWidget {
  final int totalSets;
  // False once removing the last set would leave the exercise with zero -
  // mirrors `_CurrentSetCard.canRemove`, same reasoning as `_canRemoveSet`.
  final bool canRemoveSet;
  final VoidCallback onRemoveLastSet;

  const _ExerciseCompleteCard({
    super.key,
    required this.totalSets,
    required this.canRemoveSet,
    required this.onRemoveLastSet,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.check_circle_rounded, size: 56, color: AppColors.accent),
        const SizedBox(height: AppSpacing.md),
        Text('All $totalSets sets logged', style: AppTypography.headlineSm),
        const SizedBox(height: AppSpacing.xxs),
        Text('Add another set, or move on when you\'re ready.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant)),
        if (canRemoveSet) ...[
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onRemoveLastSet();
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline_rounded,
                    size: 16, color: AppColors.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xxs),
                Text('Remove last set',
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One big, centered, tap-to-edit stat (weight or reps) for the current
/// set - the flanking +/- controls nudge it, tapping the value itself opens
/// a quick numeric-entry sheet for typing an exact number. Deliberately
/// large: with only one set ever on screen at a time, this is the page's
/// single focal control rather than one line in a dense table.
class _BigStat extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onTap;

  const _BigStat({
    required this.value,
    required this.label,
    required this.onMinus,
    required this.onPlus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepperButton(icon: Icons.remove_rounded, onTap: onMinus, size: 44),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    textAlign: TextAlign.center,
                    style: AppTypography.displayStatMobile),
                const SizedBox(height: 2),
                Text(label,
                    style: AppTypography.labelCaps
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        _StepperButton(icon: Icons.add_rounded, onTap: onPlus, size: 44),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  const _StepperButton({required this.icon, this.onTap, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              onTap == null ? Colors.transparent : AppColors.surfaceContainer,
        ),
        child: Icon(icon,
            size: size * 0.44,
            color: onTap == null
                ? AppColors.onSurfaceVariant.withOpacity(0.4)
                : AppColors.onSurface),
      ),
    );
  }
}

/// Opens a compact bottom sheet for typing a weight or rep count directly
/// instead of tapping +/- repeatedly to reach it - e.g. jumping straight to
/// 60 kg rather than 16 taps from the bar. Returns the confirmed value in
/// whatever unit [unitSuffix] names, or null if the sheet was dismissed.
Future<double?> _showQuickEntrySheet(
  BuildContext context, {
  required String title,
  required String unitSuffix,
  required double initialValue,
  required double step,
  required double min,
  bool isWholeNumber = false,
}) {
  final controller = TextEditingController(
      text: isWholeNumber
          ? initialValue.round().toString()
          : (initialValue % 1 == 0
              ? initialValue.toStringAsFixed(0)
              : initialValue.toStringAsFixed(1)));

  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
            AppSpacing.marginMobile,
            AppSpacing.marginMobile,
            AppSpacing.marginMobile,
            AppSpacing.md + MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppTypography.headlineSm),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.numberWithOptions(
                        decimal: !isWholeNumber),
                    textAlign: TextAlign.center,
                    style: AppTypography.displayStatMobile,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surfaceContainerHighest,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.inset),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.inset),
                        borderSide:
                            BorderSide(color: AppColors.accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(unitSuffix,
                      style: AppTypography.bodyLg
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryPillButton(
              label: 'Set',
              onPressed: () {
                final parsed = double.tryParse(controller.text.trim());
                if (parsed == null) {
                  Navigator.of(sheetContext).pop();
                  return;
                }
                final clamped = parsed < min ? min : parsed;
                Navigator.of(sheetContext).pop(clamped);
              },
            ),
          ],
        ),
      );
    },
  );
}

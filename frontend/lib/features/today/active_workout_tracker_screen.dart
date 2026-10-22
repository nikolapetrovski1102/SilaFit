import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/ads/ads_service.dart';
import '../../core/api/api_exception.dart';
import '../../core/live_workout/live_workout_notifier.dart';
import '../../core/live_workout/live_workout_snapshot.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/mascot/mascot_dialog.dart';
import '../../core/widgets/mascot/mascot_pose.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/upgrade_lock_card.dart';
import '../exercises/exercise_picker_sheet.dart';
import '../exercises/exercise_video_sheet.dart';
import '../exercises/exercise_web_search.dart';
import '../exercises/exercises_models.dart';
import '../notifications/notifications_repository.dart';
import '../plans/plans_controller.dart';
import '../plans/plans_repository.dart';
import '../plans/plans_screen.dart';
import '../settings/settings_controller.dart';
import 'active_workout_draft_store.dart';
import 'exercise_memory_store.dart';
import 'today_controller.dart';
import 'today_models.dart';
import 'today_repository.dart';

/// Exercises tagged with this `EquipmentType` (see the seed data in
/// `database/seed/001_SeedReferenceData.sql`) are the only ones where a
/// bar-plus-plates breakdown, or starting a fresh set at the empty bar, means
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

/// Name fragments of dumbbell exercises done with a *single* dumbbell - one
/// held in both hands (goblet squat, pullover, two-hand overhead extension)
/// or worked one arm at a time (one-arm row, concentration curl). Their
/// logged weight is already the whole load, so they're not doubled like a
/// pair would be. The catalog's EquipmentType can't say "one or two", so
/// this reads it off the name.
const _singleDumbbellNameHints = [
  'goblet',
  'single arm',
  'single-arm',
  'one arm',
  'one-arm',
  '1-arm',
  'tripod',
  'pullover',
  'pull over',
  'concentration',
  'plie',
  'sumo squat',
  'side bend',
  'knee-in',
  'pass-through',
  'two arm dumbbell overhead',
  'two arm seated dumbbell',
  'overhead dumbbell extension',
  'overhead dumbbell tricep',
  'dumbbell overhead extension',
  'dumbbell overhead tricep',
  'dumbbell tricep overhead',
  'seated dumbbell tricep extension',
  'triceps press with db',
  'overhead triceps',
  'behind head',
  'french press',
  'weighted crunch',
  'weighted ab crunch',
  '1 db',
  'dumbbell on chest',
];

/// How many dumbbells (or other implements) a set's logged weight counts for
/// in tonnage: 2 for a two-dumbbell exercise, 1 for everything else.
int _loadMultiplierFor(String? equipmentType, String exerciseName) {
  if (equipmentType != _bilateralDumbbellEquipment) return 1;
  final name = exerciseName.toLowerCase();
  return _singleDumbbellNameHints.any(name.contains) ? 1 : 2;
}

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

/// A standard Olympic bar - what the plate breakdown subtracts and where a
/// fresh barbell set starts. Only a starting point: the lifter can dial the
/// weight below it (a lighter technique bar, an EZ bar, ...).
const _barWeightKg = 20.0;

/// An EZ curl bar - lighter than the Olympic bar, so its plate math and
/// starting weight subtract this instead.
const _ezBarWeightKg = 10.0;

/// The bar a [Barbell](_barbellEquipment) exercise is loaded on, or `null`
/// when a bar-plus-plates breakdown means nothing for it: any non-barbell
/// exercise, a landmine lift (one end of the bar is anchored, so plates go on
/// one side only) and a trap bar (no standard weight).
double? _plateBarKgFor(String? equipmentType, String exerciseName) {
  if (equipmentType != _barbellEquipment) return null;
  final name = exerciseName.toLowerCase();
  if (name.contains('landmine') || name.contains('trap bar')) return null;
  if (name.contains('ez bar') || name.contains('ez-bar')) return _ezBarWeightKg;
  return _barWeightKg;
}

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
  // Bumped whenever the exercise on screen changes (advancing *or*
  // swapping in place) and used as the exercise pane's AnimatedSwitcher key,
  // so a swap - which keeps `_exerciseIndex` - still animates, while a
  // reorder - which only re-points it - doesn't.
  int _exerciseTransitionId = 0;

  // Resolved once from Settings at mount - see the class doc on _SetDraft.
  // Falls back to the spec defaults if Settings hasn't finished its own
  // first load yet (e.g. a very fast cold-start tap-through).
  late final String _weightUnit;

  // Wall-clock rather than a `Stopwatch` - a `Stopwatch` lives only in this
  // object's memory, so it can't tell a resumed screen how much time has
  // actually passed. [_startedAtUtc] is the one thing carried over from a
  // restored `ActiveWorkoutDraft` (see [_init]); `_elapsed` is recomputed
  // from it on every tick instead of tracked incrementally. Held in a
  // notifier so the per-second tick rebuilds only the clock text rather
  // than the whole tracker.
  late DateTime _startedAtUtc;
  Timer? _ticker;
  final _elapsed = ValueNotifier(Duration.zero);

  // False until [_init]'s draft lookup resolves - a single fast local
  // storage read, but still async, so the set table can't be built
  // synchronously in `initState` the way it used to be.
  bool _ready = false;

  bool _isFinishing = false;

  // Set once the session is logged server-side and its draft cleared, so
  // [dispose] doesn't write a paused draft back for a finished workout.
  bool _workoutCompleted = false;

  // Guards [_reconcileLoggedSets] against overlapping drains - the ticker and
  // a lifecycle resume can both fire while a platform-channel round-trip is in
  // flight, and replaying the same taps twice would double-log sets. Callers
  // get the in-flight future rather than a no-op, so awaiting a drain (e.g.
  // before finishing) always waits for the tap that triggered it.
  Future<void>? _reconcileInFlight;

  // Gates the "Last time" card - PRO/Advanced only, per-exercise history.
  // Checked once per purchase revision rather than per exercise switch, and
  // fetched results are cached by exercise id so flipping through exercises
  // (or reordering back to one already seen) never re-hits the network for
  // an answer already in hand.
  String? _planCode;
  int? _planRevisionChecked;
  final Map<String, List<SetLogHistoryEntry>> _exerciseHistoryCache = {};

  bool get _isPaidTier => _planCode == 'PRO' || _planCode == 'ADVANCED';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.watch<PlansController>().purchaseRevision;
    if (_planRevisionChecked != revision) {
      _planRevisionChecked = revision;
      unawaited(_loadPlanCode());
    }
  }

  Future<void> _loadPlanCode() async {
    try {
      final plan = await context.read<PlansRepository>().getActivePlanCode();
      if (!mounted) return;
      setState(() => _planCode = plan);
    } catch (_) {
      // Best-effort - the "Last time" card simply stays hidden.
    }
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
    if (!_ready || _exercises.isEmpty) return;
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

    // Last time each exercise was actually logged, if ever - a fresh set
    // starts from there instead of always resetting to the empty bar
    // or the target rep-range midpoint, matching how a lifter actually
    // plans a set ("what did I do last time").
    final memory = await ExerciseMemoryStore.instance.loadAll();

    final freshSets = widget.exercises.map((exercise) {
      final remembered = memory[exercise.exerciseId];
      return List.generate(
        exercise.targetSets <= 0 ? 1 : exercise.targetSets,
        (_) => _SetDraft(
          weightKg: remembered?.weightKg ??
              _startingWeightKgFor(exercise.equipmentType, exercise.name),
          reps: remembered?.reps ??
              ((exercise.targetRepsLow + exercise.targetRepsHigh) / 2)
                  .round()
                  .clamp(1, 999),
        ),
      );
    }).toList();

    final sessionId = _draftSessionId;
    final draft = sessionId == null
        ? null
        : await ActiveWorkoutDraftStore.instance.load(sessionId);

    // Only trusted when it matches the shape of today's exercises - a
    // draft saved against a different/older plan for the same session id
    // would otherwise restore the wrong number of exercises or sets. Also
    // requires a matching `exercises` list (absent/short on a draft saved
    // before the swap/add feature, or one saved before any swap happened),
    // so a stale-format draft falls back to the fresh plan rather than
    // resuming with mismatched exercise data. And the plan it was started
    // from must still be today's plan: switching splits before a set is
    // logged re-points the session server-side, and a same-length draft
    // would otherwise resume the old split's exercises. A pre-upgrade draft
    // has no recorded plan and is trusted on shape alone, as before.
    final draftMatchesShape = draft != null &&
        (draft.planExerciseIds.isEmpty ||
            listEquals(draft.planExerciseIds, _planExerciseIds)) &&
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
      // A draft left via Leave / back gesture resumes with the time spent
      // away cut out, so the clock picks up where it was paused.
      _startedAtUtc = draftMatchesShape
          ? draft.resumedStartedAtUtc(DateTime.now().toUtc())
          : DateTime.now().toUtc();
      _elapsed.value = DateTime.now().toUtc().difference(_startedAtUtc);
      _ready = true;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _elapsed.value = DateTime.now().toUtc().difference(_startedAtUtc);
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
    // fire on state changes, not on every ticker tick. A day with no
    // exercises has nothing to show there yet - [_addExercise] starts it
    // once the first one is added.
    if (_exercises.isNotEmpty) {
      unawaited(LiveWorkoutNotifier.instance.start(_liveSnapshot));
    }
    // Cold-start case: a "Log set" tap landed while the app was fully killed
    // (not just backgrounded), so there's no resume transition to catch it -
    // this screen re-opening from the restored draft is the only signal.
    unawaited(_reconcileLoggedSets());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _elapsed.dispose();
    // Leaving the workout room pauses it: the draft records when, and the
    // next "Continue Workout" resumes the clock without the time away. No
    // heartbeat here (unlike `_saveDraft`) - `context` is unusable in
    // dispose, and leaving isn't activity anyway.
    final sessionId = _draftSessionId;
    if (_ready && !_workoutCompleted && sessionId != null) {
      unawaited(ActiveWorkoutDraftStore.instance
          .save(_buildDraft(sessionId, pausedAtUtc: DateTime.now().toUtc())));
    }
    // Leaving the workout room ends the live timer however it happens - the
    // Leave button and Finish stop it explicitly before popping, but a back
    // swipe / system back pops straight here, and without this the Lock
    // Screen / notification clock kept running after the screen was gone.
    // Idempotent on both platforms, so the explicit stops are harmless.
    unawaited(LiveWorkoutNotifier.instance.stop());
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
  // Whether a heartbeat has already told the server a set was completed. The
  // first one that does bypasses the throttle - it's what pins today's
  // session to this split day, so a split switch right after the first set
  // must not be able to slip in before it.
  bool _reportedCompletedSets = false;

  List<String> get _planExerciseIds =>
      widget.exercises.map((e) => e.exerciseId).toList();

  /// The session id the draft (and heartbeat) is saved under: normally
  /// this screen's, but once the server has replaced a session the phone
  /// made up offline, the real one - the draft was moved there (see
  /// [TodayController.sessionIdFor]). The live surface keeps the original
  /// id, since that's what its recorded taps are keyed by.
  String? get _draftSessionId {
    final id = widget.session.workoutSessionId;
    return id == null ? null : widget.controller.sessionIdFor(id);
  }

  void _saveDraft() {
    final sessionId = _draftSessionId;
    if (sessionId == null) return;
    final now = DateTime.now();
    final hasCompletedSets =
        _setsByExercise.any((sets) => sets.any((s) => s.completed));
    if (_lastHeartbeatUtc == null ||
        now.difference(_lastHeartbeatUtc!) >= _heartbeatMinGap ||
        (hasCompletedSets && !_reportedCompletedSets)) {
      _lastHeartbeatUtc = now;
      if (hasCompletedSets) _reportedCompletedSets = true;
      unawaited(_sendWorkoutHeartbeat(sessionId, hasCompletedSets));
    }
    unawaited(ActiveWorkoutDraftStore.instance.save(_buildDraft(sessionId)));
  }

  /// The current sets/exercise/start time as a persistable draft. Pass
  /// [pausedAtUtc] when leaving the screen so the time away is cut out of
  /// the elapsed clock on resume (see [ActiveWorkoutDraft.resumedStartedAtUtc]).
  ActiveWorkoutDraft _buildDraft(String sessionId, {DateTime? pausedAtUtc}) =>
      ActiveWorkoutDraft(
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
        planExerciseIds: _planExerciseIds,
        startedAtUtc: _startedAtUtc,
        savedAtUtc: DateTime.now().toUtc(),
        pausedAtUtc: pausedAtUtc,
      );

  /// Fire-and-forget "still in the gym" ping. Fires whenever the draft is
  /// saved (screen open, set logged, exercise advanced), which is exactly the
  /// activity signal the server needs to time a set-logging nudge around real
  /// idle gaps. Best-effort; a failure never affects the workout.
  Future<void> _sendWorkoutHeartbeat(
      String sessionId, bool hasCompletedSets) async {
    try {
      await context.read<NotificationsRepository>().sendWorkoutHeartbeat(
          workoutSessionId: sessionId, hasCompletedSets: hasCompletedSets);
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
    if (_exercises.isEmpty) return;
    unawaited(LiveWorkoutNotifier.instance.update(_liveSnapshot));
  }

  /// kg per tap: a quarter-plate-per-side jump in whichever unit is active
  /// (2.5 kg, or 5 lb converted back to kg for storage) rather than a fixed
  /// kg step that would look like an odd fractional lb jump to an
  /// lb-preference lifter.
  double get _weightStepKg => _weightUnit == 'lb' ? 5 / _kgToLb : 2.5;

  /// Where a set with no history starts: the empty bar for a barbell
  /// exercise (see [_plateBarKgFor]), one weight-step for everything else,
  /// including an exercise with no `equipmentType` on record. Only a starting
  /// point - any set can be dialled down to zero.
  double _startingWeightKgFor(String? equipmentType, String exerciseName) =>
      _plateBarKgFor(equipmentType, exerciseName) ?? _weightStepKg;

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
          weightKg: last?.weightKg ??
              _startingWeightKgFor(
                  _currentExercise.equipmentType, _currentExercise.name),
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
        weightKg: remembered?.weightKg ??
            _startingWeightKgFor(exercise.equipmentType, exercise.name),
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
      _exerciseTransitionId++;
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
    final wasEmpty = _exercises.isEmpty;
    setState(() {
      _exercises.add(_toTargetExercise(picked, 1, 0, 0));
      _setsByExercise.add(_seedSets(picked, 1, 0, 0, memory));
    });
    _saveDraft();
    if (wasEmpty) {
      unawaited(LiveWorkoutNotifier.instance.start(_liveSnapshot));
    } else {
      _syncLiveWorkout();
    }
  }

  /// Opens the drag-and-drop reorder sheet and, once confirmed, applies the
  /// returned permutation to both [_exercises] and [_setsByExercise] in
  /// lockstep so a set's logged progress stays attached to its exercise
  /// across the move. [_exerciseIndex] is re-pointed at wherever the
  /// exercise that was active before the reorder ended up, rather than left
  /// at a raw index, so reordering never silently jumps the screen to a
  /// different exercise than the lifter was just looking at.
  Future<void> _reorderExercises() async {
    final order = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      builder: (_) => _ReorderExercisesSheet(exercises: _exercises),
    );
    if (order == null || !mounted) return;
    setState(() {
      final activeExerciseIndex = _exerciseIndex;
      _exercises = [for (final i in order) _exercises[i]];
      _setsByExercise = [for (final i in order) _setsByExercise[i]];
      _exerciseIndex = order.indexOf(activeExerciseIndex);
    });
    _saveDraft();
    _syncLiveWorkout();
  }

  void _adjustWeight(int index, double directionSign) {
    setState(() {
      final next = _currentSets[index].weightKg + directionSign * _weightStepKg;
      _currentSets[index].weightKg =
          next < 0 ? 0 : double.parse(next.toStringAsFixed(2));
    });
    _saveDraft();
  }

  void _setWeightDirect(int index, double kg) {
    setState(() => _currentSets[index].weightKg = kg < 0 ? 0 : kg);
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
      // See `_loadMultiplierFor` - a two-dumbbell set's logged weight is
      // per hand, so the load actually moved is double what a
      // barbell/machine/cable set of the same number would be.
      final perRepMultiplier =
          _loadMultiplierFor(_exercises[i].equipmentType, _exercises[i].name);
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
      setState(() {
        _exerciseIndex++;
        _exerciseTransitionId++;
      });
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
    final elapsedMinutes = _elapsed.value.inMinutes;
    final durationMinutes = elapsedMinutes < 1 ? 1 : elapsedMinutes;
    final outcome = await widget.controller.completeWorkout(
      workoutSessionId: sessionId,
      durationMinutes: durationMinutes,
      tonnageKg: _totalTonnageKg > 0 ? _totalTonnageKg : null,
      setLogs: _completedSetLogs,
    );
    if (!mounted) return;
    setState(() => _isFinishing = false);
    if (outcome != WorkoutCompletion.failed) {
      // Session is logged server-side now (or queued on the phone with
      // every set, to upload by itself) - the local draft would only ever
      // be stale from here on, so it's cleared regardless of whether the
      // mascot dialog below is dismissed or the screen is popped first.
      // Fire-and-forget (like `_saveDraft`) rather than awaited: nothing
      // below depends on the clear having finished, and awaiting it would
      // just be one more async gap to guard `context` against.
      _workoutCompleted = true;
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
        message: outcome == WorkoutCompletion.savedOffline
            ? 'Nice work. Saved on your phone - it\'ll upload by itself when you\'re back online.'
            : isMilestone
                ? 'You\'re on fire - $streakDays days in a row. Keep it going.'
                : 'Nice work. Your session has been logged.',
        actionLabel: 'Nice',
        showConfetti: true,
      );
      // Offline there's no ad to fetch anyway; Free accounts only.
      if (outcome != WorkoutCompletion.savedOffline) {
        unawaited(AdsService.instance.maybeShowWorkoutInterstitial());
      }
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
    // Stop before popping instead of relying only on dispose: this gives
    // the platform channel time to receive the command while the Flutter
    // engine and route are definitely still alive.
    await LiveWorkoutNotifier.instance.stop();
    if (mounted) Navigator.of(context).pop();
  }

  /// A scheduled day whose split day has no exercises on it - everything
  /// else on this screen reads the current exercise, so this stands in
  /// until the lifter adds one.
  Widget _buildEmptyWorkout() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                  AppSpacing.sm, AppSpacing.marginMobile, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _confirmExit,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.close_rounded,
                          size: 20, color: AppColors.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.marginMobile),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fitness_center_rounded,
                          size: 56, color: AppColors.accent),
                      const SizedBox(height: AppSpacing.md),
                      Text('No exercises yet', style: AppTypography.headlineSm),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                          'This day has no exercises assigned. Add one to get started.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMd
                              .copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                  AppSpacing.sm, AppSpacing.marginMobile, AppSpacing.md),
              child: PrimaryPillButton(
                label: 'Add Exercise',
                icon: Icons.add_rounded,
                onPressed: _addExercise,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      // Draft lookup (see `_init`) hasn't resolved yet - a single fast
      // local read, so this usually shows for only a frame or two.
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const SafeArea(
          child: SingleChildScrollView(
            physics: NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
            child: SkeletonDetail(rows: 4),
          ),
        ),
      );
    }
    if (_exercises.isEmpty) return _buildEmptyWorkout();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                  AppSpacing.sm, AppSpacing.marginMobile, 0),
              child: _TelemetryBar(
                onClose: _confirmExit,
                elapsed: _elapsed,
                onSwap: _swapExercise,
                onAdd: _addExercise,
                onReorder: _reorderExercises,
                onHistory: () => _showExerciseHistorySheet(
                  context,
                  exerciseId: _currentExercise.exerciseId,
                  exerciseName: _currentExercise.name,
                  weightUnit: _weightUnit,
                  cache: _exerciseHistoryCache,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, viewport) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.marginMobile),
                  // Changing exercise pages the whole pane: the finished
                  // exercise slides out to the left while the next one
                  // slides in from the right, each fading and settling in
                  // scale so it reads as moving through the program.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    reverseDuration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, if (current != null) current],
                    ),
                    transitionBuilder: (child, animation) {
                      // The outgoing child runs its animation in reverse
                      // (1 -> 0), so it needs the mirrored start offset to
                      // leave to the left instead of back to the right.
                      final isIncoming =
                          child.key == ValueKey(_exerciseTransitionId);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                                  begin: Offset(isIncoming ? 0.35 : -0.35, 0),
                                  end: Offset.zero)
                              .animate(animation),
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.94, end: 1)
                                .animate(animation),
                            child: child,
                          ),
                        ),
                      );
                    },
                    // At least the viewport's height, so the header can
                    // stay pinned up top while the set controls centre in
                    // whatever room is left - small screens still scroll.
                    child: ConstrainedBox(
                      key: ValueKey(_exerciseTransitionId),
                      constraints:
                          BoxConstraints(minHeight: viewport.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
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
                                  if (_currentExercise.demoVideoUrl != null &&
                                      isVideoUrl(
                                          _currentExercise.demoVideoUrl!))
                                    _WatchDemoChip(
                                      onTap: () => showExerciseVideoSheet(
                                        context,
                                        url: _currentExercise.demoVideoUrl!,
                                        exerciseName: _currentExercise.name,
                                      ),
                                    )
                                  else
                                    _WatchDemoChip(
                                      isSearch: true,
                                      onTap: () => openExerciseWebSearch(
                                        context,
                                        exerciseName: _currentExercise.name,
                                      ),
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
                                    completedSets:
                                        _completedSetsInCurrentExercise,
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
                                style: AppTypography.bodyMd.copyWith(
                                    color: AppColors.onSurfaceVariant),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                                        barKg: _plateBarKgFor(
                                            _currentExercise.equipmentType,
                                            _currentExercise.name),
                                        suggestWeightIncrease:
                                            _suggestWeightIncrease,
                                        canRemove: _canRemoveSet,
                                        onLog: () => _logSet(_activeSetIndex!),
                                        onRemove: () =>
                                            _removeSet(_activeSetIndex!),
                                        onWeightDelta: (sign) => _adjustWeight(
                                            _activeSetIndex!, sign),
                                        onRepsDelta: (delta) => _adjustReps(
                                            _activeSetIndex!, delta),
                                        onWeightDirectKg: (kg) =>
                                            _setWeightDirect(
                                                _activeSetIndex!, kg),
                                        onRepsDirect: (reps) => _setRepsDirect(
                                            _activeSetIndex!, reps),
                                      )
                                    : _ExerciseCompleteCard(
                                        key: const ValueKey('complete'),
                                        totalSets: _currentSets.length,
                                        canRemoveSet: _canRemoveSet,
                                        onRemoveLastSet: () =>
                                            _removeSet(_currentSets.length - 1),
                                      ),
                              ),
                              if (_isPaidTier)
                                _LastTimeRow(
                                  key: ValueKey(
                                      'history-${_currentExercise.exerciseId}'),
                                  exerciseId: _currentExercise.exerciseId,
                                  exerciseName: _currentExercise.name,
                                  weightUnit: _weightUnit,
                                  cache: _exerciseHistoryCache,
                                ),
                            ],
                          ),
                          // Bottom anchor for `spaceBetween` - keeps a
                          // little extra air under the set block so it sits
                          // just above true centre.
                          const SizedBox(height: AppSpacing.xxxl),
                        ],
                      ),
                    ),
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
    );
  }
}

class _TelemetryBar extends StatelessWidget {
  final VoidCallback onClose;
  final ValueListenable<Duration> elapsed;
  final VoidCallback onSwap;
  final VoidCallback onAdd;
  final VoidCallback onReorder;
  final VoidCallback onHistory;

  const _TelemetryBar({
    required this.onClose,
    required this.elapsed,
    required this.onSwap,
    required this.onAdd,
    required this.onReorder,
    required this.onHistory,
  });

  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

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
        // Balances the history button on the right so the elapsed time
        // stays visually centered.
        const SizedBox(width: 40),
        const Spacer(),
        Icon(Icons.timer_outlined, size: 16, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 6),
        ValueListenableBuilder(
          valueListenable: elapsed,
          builder: (context, value, _) => Text(_formatElapsed(value),
              style: AppTypography.numericUnit
                  .copyWith(color: AppColors.onSurface)),
        ),
        const Spacer(),
        // Always here, every tier - the sheet itself handles loading, an
        // empty history and the Free-tier upgrade prompt.
        Tooltip(
          message: 'Exercise history',
          child: GestureDetector(
            onTap: onHistory,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.history_rounded,
                  size: 22, color: AppColors.onSurface),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: _ExerciseMenuChip(
                onSwap: onSwap, onAdd: onAdd, onReorder: onReorder),
          ),
        ),
      ],
    );
  }
}

/// Compact icon-only chip opening a bottom sheet with "Swap exercise" /
/// "Add exercise" / "Reorder exercises" - the entry point for the
/// session-local exercise swap/add/reorder feature (see
/// `_swapExercise`/`_addExercise`/`_reorderExercises`). A plain circular
/// icon rather than another labeled pill like [_WatchDemoChip], since it's
/// always present (unlike the demo chip, which only shows up when the
/// exercise has a reference video) and doesn't need to compete for width in
/// the header row.
class _ExerciseMenuChip extends StatelessWidget {
  final VoidCallback onSwap;
  final VoidCallback onAdd;
  final VoidCallback onReorder;

  const _ExerciseMenuChip({
    required this.onSwap,
    required this.onAdd,
    required this.onReorder,
  });

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
            ListTile(
              leading: Icon(Icons.reorder_rounded, color: AppColors.onSurface),
              title: Text('Reorder exercises', style: AppTypography.bodyMd),
              subtitle: Text('Drag to change what comes next',
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.onSurfaceVariant)),
              onTap: () => Navigator.of(sheetContext).pop(onReorder),
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
  /// True for exercises with no demo video - opens a web search instead of
  /// the in-app video sheet.
  final bool isSearch;

  final VoidCallback onTap;

  const _WatchDemoChip({
    this.isSearch = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = isSearch
        ? Icons.travel_explore_rounded
        : Icons.play_circle_fill_rounded;
    final label = isSearch ? 'Search form' : 'Watch form';

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
            Icon(icon, size: 16, color: AppColors.accent),
            const SizedBox(width: 4),
            Text(label,
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
  // The bar this exercise is loaded on, or null when a bar-plus-plates
  // breakdown means nothing for it (see `_plateBarKgFor`).
  final double? barKg;
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
    required this.barKg,
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
      min: 0,
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
    final bar = barKg;
    // Names the bar as well as the plates, so the per-side figures visibly
    // add up to the total (27.5 kg reads "20 kg bar + 2.5 + 1.25 kg each
    // side", not a bare "Per side: 2.5 + 1.25" that looks like the total).
    String? plateLine;
    if (bar != null) {
      final plates = _plateBreakdown(set.weightKg, bar, weightUnit);
      if (plates.isNotEmpty) {
        plateLine = '${_formatWeight(bar, weightUnit)} $weightUnit bar + '
            '${plates.map((p) => p % 1 == 0 ? p.toStringAsFixed(0) : p.toStringAsFixed(2)).join(' + ')} $weightUnit each side';
      } else if ((set.weightKg - bar).abs() < 0.01) {
        plateLine = 'Empty bar';
      }
    }
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
        const SizedBox(height: AppSpacing.xxl),
        _BigStat(
          value: '${_formatWeight(set.weightKg, weightUnit)} $weightUnit',
          label: 'WEIGHT',
          onMinus: () => onWeightDelta(-1),
          onPlus: () => onWeightDelta(1),
          onTap: () => _editWeight(context),
        ),
        if (plateLine != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(plateLine,
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
        const SizedBox(height: AppSpacing.xxl),
        _BigStat(
          value: '${set.reps} reps',
          label: 'REPS',
          onMinus: () => onRepsDelta(-1),
          onPlus: () => onRepsDelta(1),
          onTap: () => _editReps(context),
        ),
        const SizedBox(height: AppSpacing.xxxl),
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

/// Fetches [exerciseId]'s history through [cache] (owned by the tracker
/// screen's State, outliving any one row or sheet), so revisiting an
/// exercise already fetched this session never re-hits the network. Throws
/// [ApiException] - a 403 for a Free-tier account.
Future<List<SetLogHistoryEntry>> _loadExerciseHistory(BuildContext context,
    String exerciseId, Map<String, List<SetLogHistoryEntry>> cache) async {
  final cached = cache[exerciseId];
  if (cached != null) return cached;
  final entries =
      await context.read<TodayRepository>().getExerciseHistory(exerciseId);
  cache[exerciseId] = entries;
  return entries;
}

/// The history endpoint includes the session being logged right now, so a
/// set ticked off a minute ago would otherwise read as "last time". Workout
/// sessions are one per day, so anything completed today is this one.
List<SetLogHistoryEntry> _previousSessionsOnly(
    List<SetLogHistoryEntry> entries) {
  final today = DateUtils.dateOnly(DateTime.now());
  return entries
      .where((e) => DateUtils.dateOnly(e.completedAtUtc.toLocal()) != today)
      .toList();
}

void _showExerciseHistorySheet(
  BuildContext context, {
  required String exerciseId,
  required String exerciseName,
  required String weightUnit,
  required Map<String, List<SetLogHistoryEntry>> cache,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (_) => _ExerciseHistorySheet(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      weightUnit: weightUnit,
      cache: cache,
    ),
  );
}

/// Every logged session of one exercise, most recent first. Opened from the
/// tracker's top bar (always there, for every tier) and from the "Last time"
/// row. Loads with a skeleton, says so plainly when there's nothing yet, and
/// shows Free accounts what they'd unlock instead of an empty sheet.
class _ExerciseHistorySheet extends StatefulWidget {
  final String exerciseId;
  final String exerciseName;
  final String weightUnit;
  final Map<String, List<SetLogHistoryEntry>> cache;

  const _ExerciseHistorySheet({
    required this.exerciseId,
    required this.exerciseName,
    required this.weightUnit,
    required this.cache,
  });

  @override
  State<_ExerciseHistorySheet> createState() => _ExerciseHistorySheetState();
}

class _ExerciseHistorySheetState extends State<_ExerciseHistorySheet> {
  List<SetLogHistoryEntry>? _entries;
  bool _locked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entries = widget.cache[widget.exerciseId];
    if (_entries == null) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final entries =
          await _loadExerciseHistory(context, widget.exerciseId, widget.cache);
      if (!mounted) return;
      setState(() => _entries = entries);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => e.isForbidden ? _locked = true : _error = e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load your history. Please try again.");
    }
  }

  void _openPlans() {
    Navigator.of(context)
      ..pop()
      ..push(MaterialPageRoute(builder: (_) => const PlansScreen()));
  }

  List<Widget> _buildBody() {
    if (_locked) {
      return [
        UpgradeLockCard(
          title: 'See every set you\'ve logged',
          message: 'Pro and Advanced show your past sessions for each '
              'exercise right inside your workout.',
          actionLabel: 'See plans',
          onUnlock: _openPlans,
        ),
      ];
    }
    if (_error != null) {
      return [
        const SizedBox(height: AppSpacing.xl),
        Text(_error!,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton(
            onPressed: _load,
            child: Text('RETRY',
                style:
                    AppTypography.labelCaps.copyWith(color: AppColors.accent)),
          ),
        ),
      ];
    }
    final entries = _entries;
    if (entries == null) {
      return const [SkeletonList(count: 3, leading: false)];
    }

    final previous = _previousSessionsOnly(entries);
    if (previous.isEmpty) {
      return [
        const SizedBox(height: AppSpacing.xl),
        Icon(Icons.history_rounded,
            size: 40, color: AppColors.onSurfaceVariant),
        const SizedBox(height: AppSpacing.sm),
        Text('No history yet',
            textAlign: TextAlign.center, style: AppTypography.headlineSm),
        const SizedBox(height: AppSpacing.xxs),
        Text(
            'Finish a set of this exercise and it will show up here next time.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant)),
      ];
    }

    final grouped = <DateTime, List<SetLogHistoryEntry>>{};
    for (final entry in previous) {
      grouped
          .putIfAbsent(
              DateUtils.dateOnly(entry.completedAtUtc.toLocal()), () => [])
          .add(entry);
    }
    return [
      for (final day in grouped.entries) ...[
        _HistorySessionCard(
          dateLabel: DateFormat('EEEE, MMM d').format(day.key),
          sets: day.value,
          weightUnit: widget.weightUnit,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
            AppSpacing.lg, AppSpacing.marginMobile, AppSpacing.xl),
        children: [
          Text(widget.exerciseName, style: AppTypography.headlineSm),
          const SizedBox(height: AppSpacing.xxs),
          Text('Your recent sessions for this exercise',
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.lg),
          ..._buildBody(),
        ],
      ),
    );
  }
}

/// PRO/Advanced-only "what did I do last time" row under the set controls -
/// a glanceable shortcut into [_ExerciseHistorySheet]. A short bone stands
/// in while it loads; it stays hidden on failure or when there's no earlier
/// session (the top-bar history button still says so explicitly). Keyed on
/// the exercise id by the caller, so a fresh instance mounts per exercise.
class _LastTimeRow extends StatefulWidget {
  final String exerciseId;
  final String exerciseName;
  final String weightUnit;
  final Map<String, List<SetLogHistoryEntry>> cache;

  const _LastTimeRow({
    super.key,
    required this.exerciseId,
    required this.exerciseName,
    required this.weightUnit,
    required this.cache,
  });

  @override
  State<_LastTimeRow> createState() => _LastTimeRowState();
}

class _LastTimeRowState extends State<_LastTimeRow> {
  List<SetLogHistoryEntry>? _entries;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _entries = widget.cache[widget.exerciseId];
    if (_entries == null) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final entries =
          await _loadExerciseHistory(context, widget.exerciseId, widget.cache);
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final entries = _entries;
    if (entries == null) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.md + AppSpacing.xs),
        child: Skeleton(child: Bone.text(width: 150)),
      );
    }
    final previous = _previousSessionsOnly(entries);
    if (previous.isEmpty) return const SizedBox.shrink();
    final mostRecent = previous.first;
    final unit = widget.weightUnit;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => _showExerciseHistorySheet(
            context,
            exerciseId: widget.exerciseId,
            exerciseName: widget.exerciseName,
            weightUnit: unit,
            cache: widget.cache,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.xs, horizontal: AppSpacing.xxs),
            child: Row(
              children: [
                Icon(Icons.history_rounded,
                    size: 18, color: AppColors.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Last time: ${_formatWeight(mostRecent.weightKg, unit)} $unit × ${mostRecent.reps}',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistorySessionCard extends StatelessWidget {
  final String dateLabel;
  final List<SetLogHistoryEntry> sets;
  final String weightUnit;

  const _HistorySessionCard(
      {required this.dateLabel, required this.sets, required this.weightUnit});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionEyebrow(dateLabel),
          const SizedBox(height: AppSpacing.sm),
          for (final set in sets)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text('Set ${set.setNumber}',
                        style: AppTypography.bodyMd
                            .copyWith(color: AppColors.onSurfaceVariant)),
                  ),
                  Expanded(
                    child: Text(
                        '${_formatWeight(set.weightKg, weightUnit)} $weightUnit × ${set.reps}',
                        style: AppTypography.numericUnit
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
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
        _StepperButton(icon: Icons.remove_rounded, onTap: onMinus, size: 48),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Scales down rather than wrapping for long readouts
                // (e.g. "102.5 lb") on narrow phones.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value,
                      textAlign: TextAlign.center,
                      style: AppTypography.displayStat),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(label,
                    style: AppTypography.labelCaps
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        _StepperButton(icon: Icons.add_rounded, onTap: onPlus, size: 48),
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

/// Drag-and-drop reorder sheet for this session's exercise order - opened
/// from [_ExerciseMenuChip]'s "Reorder exercises" option (see
/// `_reorderExercises`). Works on a local copy of the order (a permutation
/// of indices into [exercises]) so nothing on the tracker screen changes
/// until "Done" is tapped; dismissing the sheet any other way pops `null`,
/// which the caller treats as a no-op.
class _ReorderExercisesSheet extends StatefulWidget {
  final List<TargetExercise> exercises;

  const _ReorderExercisesSheet({required this.exercises});

  @override
  State<_ReorderExercisesSheet> createState() => _ReorderExercisesSheetState();
}

class _ReorderExercisesSheetState extends State<_ReorderExercisesSheet> {
  late final List<int> _order =
      List<int>.generate(widget.exercises.length, (i) => i);

  void _onReorder(int oldIndex, int newIndex) {
    setState(() => _order.insert(newIndex, _order.removeAt(oldIndex)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            left: AppSpacing.marginMobile,
            right: AppSpacing.marginMobile,
            top: AppSpacing.marginMobile,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reorder exercises', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.xxs),
            Text('Press and drag the handle to change what comes next.',
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _order.length,
                onReorderItem: _onReorder,
                itemBuilder: (context, index) => _ReorderExerciseTile(
                  key: ValueKey(_order[index]),
                  index: index,
                  exercise: widget.exercises[_order[index]],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryPillButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(_order),
            ),
          ],
        ),
      ),
    );
  }
}

/// One draggable row in [_ReorderExercisesSheet]: position number, exercise
/// name/muscle group, and a trailing drag handle that's the only part of
/// the row wired to start a drag - so nothing fires on an accidental tap
/// elsewhere on the tile.
class _ReorderExerciseTile extends StatelessWidget {
  final int index;
  final TargetExercise exercise;

  const _ReorderExerciseTile({
    super.key,
    required this.index,
    required this.exercise,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.inset),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('${index + 1}',
                style: AppTypography.labelCaps
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.name, style: AppTypography.bodyMd),
                Text(exercise.muscleGroup,
                    style: AppTypography.labelSm
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxs),
              child: Icon(Icons.drag_handle_rounded,
                  color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

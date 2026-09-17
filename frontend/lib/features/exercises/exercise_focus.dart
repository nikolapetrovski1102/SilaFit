/// Resolves which coarse exercise muscle groups a custom split day should show
/// suggestions for, from the day's title/focus and the exercises already on it.
///
/// The catalogue only knows six coarse groups, so finer intent in a day title
/// ("triceps", "delts", "quads") is folded onto those groups by [_keywords].
library;

/// Coarse muscle groups understood by the exercise catalogue
/// (`CK_Exercises_MuscleGroup`), in the order a day that names several should
/// present them.
const List<String> kExerciseMuscleGroups = [
  'chest',
  'back',
  'legs',
  'shoulders',
  'arms',
  'core',
];

/// Intent words mapped to the catalogue's coarse groups. Matching is whole-word
/// (see [_hasWord]) so "warm up" never reads as "arm". Session-shape words such
/// as "push"/"pull"/"upper"/"lower" are deliberately absent: they name a format,
/// not a muscle, so those days fall through to the exercises already added.
const Map<String, List<String>> _keywords = {
  'chest': [
    'chest',
    'chests',
    'pec',
    'pecs',
    'bench',
    'bench press',
    'push up',
    'push ups',
    'pushup',
    'pushups',
  ],
  'back': [
    'back',
    'lat',
    'lats',
    'row',
    'rows',
    'pull up',
    'pull ups',
    'pullup',
    'pullups',
    'trap',
    'traps',
    'deadlift',
    'deadlifts',
  ],
  'legs': [
    'leg',
    'legs',
    'quad',
    'quads',
    'hamstring',
    'hamstrings',
    'glute',
    'glutes',
    'calf',
    'calves',
    'squat',
    'squats',
    'lunge',
    'lunges',
    'hip',
    'hips',
  ],
  'shoulders': [
    'shoulder',
    'shoulders',
    'delt',
    'delts',
    'overhead press',
    'ohp',
    'lateral raise',
    'lateral raises',
  ],
  'arms': [
    'arm',
    'arms',
    'bicep',
    'biceps',
    'tricep',
    'triceps',
    'curl',
    'curls',
    'forearm',
    'forearms',
    'grip',
  ],
  'core': [
    'core',
    'abs',
    'ab',
    'abdominal',
    'abdominals',
    'oblique',
    'obliques',
    'plank',
    'planks',
  ],
};

/// The muscle groups a piece of text points at, deduped and in [kExerciseMuscleGroups]
/// order so the same title always yields the same list.
List<String> muscleGroupsInText(String text) {
  if (text.trim().isEmpty) return const [];
  final normalized = _normalize(text);
  return [
    for (final group in kExerciseMuscleGroups)
      if (_keywords[group]!.any((word) => _hasWord(normalized, word))) group,
  ];
}

/// The ordered, deduped groups a day should suggest for.
///
/// [fromTitle] is true when the day's own wording named at least one muscle, so
/// the UI can head the list with that focus ("Suggested for arms") versus
/// falling back to the exercises already added ("More for this day").
class ExerciseFocus {
  final List<String> muscleGroups;
  final bool fromTitle;

  const ExerciseFocus({required this.muscleGroups, required this.fromTitle});

  static const empty = ExerciseFocus(muscleGroups: [], fromTitle: false);

  bool get isEmpty => muscleGroups.isEmpty;
}

/// Blends the two signals the picker has:
///
/// 1. Groups named in the day title/focus - explicit intent, so they lead.
/// 2. Groups of exercises already on the day, in the order the caller supplies
///    them (most recently added first), so a generically titled day ("Push")
///    keeps suggesting more of whatever the user has been adding - chest after
///    a chest movement, arms after a triceps movement.
///
/// Returns [ExerciseFocus.empty] when neither signal exists, which the picker
/// reads as "show the generic best-for-you list".
ExerciseFocus resolveExerciseFocus({
  String? title,
  String? focus,
  List<String> existingExerciseGroups = const [],
}) {
  final titleGroups = muscleGroupsInText('${title ?? ''} ${focus ?? ''}');

  final merged = <String>[];
  for (final group in titleGroups) {
    if (!merged.contains(group)) merged.add(group);
  }
  for (final group in existingExerciseGroups) {
    if (group.isEmpty || merged.contains(group)) continue;
    merged.add(group);
  }

  return ExerciseFocus(muscleGroups: merged, fromTitle: titleGroups.isNotEmpty);
}

String _normalize(String text) =>
    ' ${text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';

bool _hasWord(String normalized, String word) => normalized.contains(' $word ');

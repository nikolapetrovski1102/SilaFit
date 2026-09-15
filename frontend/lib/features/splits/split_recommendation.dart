import 'splits_models.dart';

/// One split plus the score/reason behind its placement. [reason] is the
/// plain-language sentence the UI shows for why this protocol is the pick.
class SplitMatch {
  final WorkoutSplit split;
  final int score;
  final String reason;

  const SplitMatch({
    required this.split,
    required this.score,
    required this.reason,
  });
}

/// Display label for a `WorkoutSplits.RecommendedGoal` / profile goal value.
String splitGoalLabel(String goal) => switch (goal) {
      'BuildMuscle' => 'Build Muscle',
      'LoseFat' => 'Lose Fat',
      'MaintainActive' => 'Stay Active',
      _ => goal,
    };

/// Display label for a `WorkoutSplits.Category` value - the raw enum-ish
/// strings ('PushPullLegs', 'GluteFocus', ...) read badly in a sentence.
String splitCategoryLabel(String category) => switch (category) {
      'PushPullLegs' => 'Push · Pull · Legs',
      'UpperLower' => 'Upper · Lower',
      'FullBody' => 'Full Body',
      'ArnoldSplit' => 'Arnold Split',
      'BroSplit' => 'Bro Split',
      'GluteFocus' => 'Glute & Core',
      _ => category,
    };

/// Ranks the split library for one user, best first.
///
/// The backend already scores each split against the caller's profile (goal
/// match + age/BMI level fit + category affinity) and ships that as
/// [WorkoutSplit.matchScore]/[WorkoutSplit.matchReason]; this just sorts by it
/// so the hero is `first` and the shortlist is the rows after it.
///
/// When the score is absent - a guest/pre-onboarding payload from an older
/// server, or a test - the legacy local heuristic stands in: goal match
/// dominates, system-default curation is the fallback, and list position
/// mirrors the backend's `SortOrder` as a stable tie-breaker. The choice is
/// made for the whole list (never per-row) because the two schemes use
/// different score scales and must not be compared against each other.
List<SplitMatch> rankSplitMatches(List<WorkoutSplit> splits) {
  final useServerScores = splits.every((s) => s.matchScore != null);
  final matches = <SplitMatch>[];
  for (var i = 0; i < splits.length; i++) {
    final split = splits[i];
    final score = useServerScores
        ? split.matchScore!
        : (split.matchesGoal ? 1000 : 0) +
            (split.isSystemDefault ? 100 : 0) +
            (splits.length - i);
    matches.add(SplitMatch(
      split: split,
      score: score,
      reason: (useServerScores ? split.matchReason : null) ?? _reasonFor(split),
    ));
  }
  matches.sort((a, b) => b.score.compareTo(a.score));
  return matches;
}

String _reasonFor(WorkoutSplit split) {
  final parts = <String>[];
  if (split.matchesGoal && split.recommendedGoal != null) {
    parts.add('Matched to your ${splitGoalLabel(split.recommendedGoal!)} goal');
  } else if (split.isSystemDefault) {
    parts.add('Featured starter protocol');
  } else {
    parts.add('${splitCategoryLabel(split.category)} training');
  }
  parts.add(split.level);
  parts.add('${split.durationDays} days');
  return parts.join(' · ');
}

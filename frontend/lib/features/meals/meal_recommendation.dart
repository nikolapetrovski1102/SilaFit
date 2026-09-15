import 'meal_models.dart';

/// One curated meal plus the score/reason behind its placement. The score is
/// only ever compared against other matches; [reason] is the sentence the UI
/// shows to explain *why* this meal is being put in front of the user.
class MealMatch {
  final MealSuggestion suggestion;
  final double score;
  final String reason;

  const MealMatch({
    required this.suggestion,
    required this.score,
    required this.reason,
  });
}

/// The meal slot the local clock currently falls in, so a 9am recommendation
/// isn't a steak dinner. Mirrors the four seeded meal types.
String mealSlotForTime(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour < 11) return 'Breakfast';
  if (hour >= 11 && hour < 15) return 'Lunch';
  if (hour >= 15 && hour < 21) return 'Dinner';
  return 'Snack';
}

/// Ranks the curated library against what's actually left in the user's day.
///
/// This is the app's answer to "more meals shouldn't mean more scrolling": a
/// catalog of hundreds still opens on the one meal that's best right now, and
/// the rest stays behind a deliberate browse action. Weighted signals:
///  - person fit   - the server's score for this meal against the user's own
///                   nutrition targets (which derive from their
///                   height/weight/age/gender/goal), blended 35/65 with the
///                   day signals; omitted when the payload isn't scored, so
///                   the day signals decide on their own
///  - calorie fit  - how close the meal is to the user's remaining kcal
///  - protein fit  - how much of the day's remaining protein it closes
///  - time-of-day fit - breakfast in the morning, dinner at night
///
/// [day] is the selected day's composed totals; when it's null (the day half
/// hasn't loaded yet) ranking falls back to person fit + time-of-day +
/// curation order, so the UI still gets a sensible pick instead of whatever
/// row happened to come first.
List<MealMatch> rankMealMatches(
  List<MealSuggestion> suggestions, {
  MealDay? day,
  DateTime? now,
}) {
  if (suggestions.isEmpty) return const [];

  final slot = mealSlotForTime(now ?? DateTime.now());
  final remainingKcal = day == null
      ? null
      : (day.remainingCalories > 0 ? day.remainingCalories : 0);
  final proteinGap =
      day == null ? null : day.targets.targetProteinG - day.consumedProteinG;

  final matches = [
    for (final suggestion in suggestions)
      _matchFor(
        suggestion,
        remainingKcal: remainingKcal,
        proteinGap: proteinGap,
        slot: slot,
      ),
  ]..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.suggestion.sortOrder.compareTo(b.suggestion.sortOrder);
    });

  return matches;
}

MealMatch _matchFor(
  MealSuggestion suggestion, {
  required int? remainingKcal,
  required int? proteinGap,
  required String slot,
}) {
  double kcalFit;
  if (remainingKcal == null) {
    // No day totals to fit against - stay neutral so time-of-day decides.
    kcalFit = 0.5;
  } else if (remainingKcal <= 0) {
    // Already over budget - the most a meal can do now is stay light.
    kcalFit = _clamp01(1 - suggestion.caloriesKcal / 800);
  } else {
    // Tolerance widens for a big remaining budget so "closest to target"
    // doesn't collapse into "biggest meal" on a 1,500 kcal gap.
    final tolerance = remainingKcal < 350 ? 350.0 : remainingKcal.toDouble();
    kcalFit = _clamp01(
        1 - (suggestion.caloriesKcal - remainingKcal).abs() / tolerance);
  }

  double proteinFit;
  if (proteinGap == null || proteinGap <= 0) {
    proteinFit = _clamp01(suggestion.proteinG / 40);
  } else {
    proteinFit = _clamp01(suggestion.proteinG / proteinGap);
  }

  final slotFit = suggestion.mealType == slot ? 1.0 : 0.0;
  // The day/time signals keep their original 5:3:2 weighting (so behaviour for
  // a payload the server didn't score is unchanged); the server's person-fit
  // score is blended in on top when present.
  final dayScore = (kcalFit * 0.5) + (proteinFit * 0.3) + (slotFit * 0.2);
  final personFit = suggestion.matchScore == null
      ? null
      : _clamp01(suggestion.matchScore! / 100);
  final score =
      personFit == null ? dayScore : (dayScore * 0.65) + (personFit * 0.35);

  return MealMatch(
    suggestion: suggestion,
    score: score,
    reason: _reasonFor(
      suggestion,
      remainingKcal: remainingKcal,
      proteinGap: proteinGap,
      slot: slot,
    ),
  );
}

String _reasonFor(
  MealSuggestion suggestion, {
  required int? remainingKcal,
  required int? proteinGap,
  required String slot,
}) {
  // The server's person-fit sentence, when present, leads; the day-specific
  // framing is appended so the two signals both show.
  final personReason = suggestion.matchReason;
  if (remainingKcal != null && remainingKcal > 0) {
    if (personReason != null) {
      return '$personReason · $remainingKcal kcal left today';
    }
    if (proteinGap != null && proteinGap > 0 && suggestion.proteinG >= 20) {
      return 'Best match for your $remainingKcal kcal remaining · '
          '${suggestion.proteinG}g protein toward today\'s target';
    }
    return 'Best match for your $remainingKcal kcal remaining';
  }
  if (remainingKcal != null) {
    return personReason ??
        'You\'re at today\'s calorie target - lightest options first';
  }
  return personReason ??
      'A strong $slot option · ${suggestion.proteinG}g protein';
}

double _clamp01(num value) => value.clamp(0.0, 1.0).toDouble();

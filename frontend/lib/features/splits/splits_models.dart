/// Mirrors `Silen.Common.Models.SplitModels` / `Silen.Common.Dtos.SplitsDtos`.
class WorkoutSplit {
  final String splitId;
  final String name;
  final String category;
  final String level;
  final int durationDays;
  final String? description;
  final String? heroImageUrl;
  final bool isSystemDefault;
  // 'Public' (every user), 'Shared' (assigned users only) or 'Private' (owner
  // only). The backend has already filtered the list/detail to what this caller
  // may see, so this is presentation metadata (e.g. a "from your coach" badge).
  final String visibility;
  // The onboarding goal ('BuildMuscle'/'LoseFat'/'MaintainActive') this split
  // is tagged for, or null if it isn't goal-tagged; matchesGoal is computed
  // server-side against the caller's own profile goal (false for guests/
  // unauthenticated callers or users without a matching profile).
  final String? recommendedGoal;
  final bool matchesGoal;

  // Person-fit signals computed server-side from the caller's profile (goal +
  // age/BMI-derived level fit + category affinity). Null on payloads that
  // predate this field (or in tests), in which case the local fallback
  // heuristic in split_recommendation.dart takes over.
  final int? matchScore;
  final String? matchReason;

  const WorkoutSplit({
    required this.splitId,
    required this.name,
    required this.category,
    required this.level,
    required this.durationDays,
    this.description,
    this.heroImageUrl,
    required this.isSystemDefault,
    this.visibility = 'Public',
    this.recommendedGoal,
    this.matchesGoal = false,
    this.matchScore,
    this.matchReason,
  });

  factory WorkoutSplit.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return WorkoutSplit(
      splitId: map['splitId'] as String,
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? '',
      level: map['level'] as String? ?? '',
      durationDays: map['durationDays'] as int? ?? 0,
      description: map['description'] as String?,
      heroImageUrl: map['heroImageUrl'] as String?,
      isSystemDefault: map['isSystemDefault'] as bool? ?? false,
      visibility: map['visibility'] as String? ?? 'Public',
      recommendedGoal: map['recommendedGoal'] as String?,
      matchesGoal: map['matchesGoal'] as bool? ?? false,
      matchScore: map['matchScore'] as int?,
      matchReason: map['matchReason'] as String?,
    );
  }
}

class SplitDay {
  final String splitDayId;
  final int dayIndex;
  final String title;
  final String? focusLabel;
  final int estimatedMinutes;
  final bool isRestDay;

  const SplitDay({
    required this.splitDayId,
    required this.dayIndex,
    required this.title,
    this.focusLabel,
    required this.estimatedMinutes,
    required this.isRestDay,
  });

  factory SplitDay.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return SplitDay(
      splitDayId: map['splitDayId'] as String,
      dayIndex: map['dayIndex'] as int? ?? 0,
      title: map['title'] as String? ?? '',
      focusLabel: map['focusLabel'] as String?,
      estimatedMinutes: map['estimatedMinutes'] as int? ?? 0,
      isRestDay: map['isRestDay'] as bool? ?? false,
    );
  }
}

class SplitDayExercise {
  final String exerciseId;
  final String name;
  final int sortOrder;
  final int targetSets;
  final int targetRepsLow;
  final int targetRepsHigh;

  const SplitDayExercise({
    required this.exerciseId,
    required this.name,
    required this.sortOrder,
    required this.targetSets,
    required this.targetRepsLow,
    required this.targetRepsHigh,
  });

  factory SplitDayExercise.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return SplitDayExercise(
      exerciseId: map['exerciseId'] as String,
      name: map['name'] as String? ?? '',
      sortOrder: map['sortOrder'] as int? ?? 0,
      targetSets: map['targetSets'] as int? ?? 0,
      targetRepsLow: map['targetRepsLow'] as int? ?? 0,
      targetRepsHigh: map['targetRepsHigh'] as int? ?? 0,
    );
  }
}

class SplitDayWithExercises {
  final SplitDay day;
  final List<SplitDayExercise> exercises;

  const SplitDayWithExercises({required this.day, required this.exercises});

  factory SplitDayWithExercises.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return SplitDayWithExercises(
      day: SplitDay.fromJson(map['day']),
      exercises: (map['exercises'] as List<dynamic>? ?? [])
          .map((e) => SplitDayExercise.fromJson(e))
          .toList(),
    );
  }
}

class SplitDetail {
  final WorkoutSplit split;
  final List<SplitDayWithExercises> days;

  const SplitDetail({required this.split, required this.days});

  factory SplitDetail.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return SplitDetail(
      split: WorkoutSplit.fromJson(map['split']),
      days: (map['days'] as List<dynamic>? ?? [])
          .map((e) => SplitDayWithExercises.fromJson(e))
          .toList(),
    );
  }
}

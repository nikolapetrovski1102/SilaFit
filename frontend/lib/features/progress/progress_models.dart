/// Mirrors `Silen.Common.Dtos.ProgressDtos`.
class ProgressOverview {
  final int currentStreakDays;
  final int weeklyCompliancePercent;
  final int completedSessions;
  final int scheduledSessions;
  final double totalTonnageKg;
  final double avgRpe;
  final List<HeatmapDay> heatmap;
  final List<String> insights;

  const ProgressOverview({
    required this.currentStreakDays,
    required this.weeklyCompliancePercent,
    required this.completedSessions,
    required this.scheduledSessions,
    required this.totalTonnageKg,
    required this.avgRpe,
    required this.heatmap,
    required this.insights,
  });

  factory ProgressOverview.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return ProgressOverview(
      currentStreakDays: map['currentStreakDays'] as int? ?? 0,
      weeklyCompliancePercent: map['weeklyCompliancePercent'] as int? ?? 0,
      completedSessions: map['completedSessions'] as int? ?? 0,
      scheduledSessions: map['scheduledSessions'] as int? ?? 0,
      totalTonnageKg: (map['totalTonnageKg'] as num?)?.toDouble() ?? 0,
      avgRpe: (map['avgRpe'] as num?)?.toDouble() ?? 0,
      heatmap: (map['heatmap'] as List<dynamic>? ?? [])
          .map((e) => HeatmapDay.fromJson(e))
          .toList(),
      insights: (map['insights'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }
}

class HeatmapDay {
  final DateTime date;
  final String status;
  // Only populated for logged/completed sessions - null for a day that's
  // merely scheduled or missed, not zero (zero would understate a rest day
  // as if it were a tracked, weightless session).
  final double? tonnageKg;
  final double? rpeScore;

  const HeatmapDay({
    required this.date,
    required this.status,
    this.tonnageKg,
    this.rpeScore,
  });

  factory HeatmapDay.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return HeatmapDay(
        date: DateTime.parse(map['date'] as String),
        status: map['status'] as String? ?? 'Scheduled',
        tonnageKg: (map['tonnageKg'] as num?)?.toDouble(),
        rpeScore: (map['rpeScore'] as num?)?.toDouble());
  }
}

/// The heaviest set ever logged for one exercise. Mirrors
/// `Silen.Common.Dtos.PersonalRecordDto`. [previousBestWeightKg] is null
/// when this is the only set ever logged for the exercise - callers show no
/// delta badge in that case rather than a misleading "+0".
class PersonalRecord {
  final String exerciseId;
  final String exerciseName;
  final double weightKg;
  final int reps;
  final DateTime achievedAtUtc;
  final double? previousBestWeightKg;

  const PersonalRecord({
    required this.exerciseId,
    required this.exerciseName,
    required this.weightKg,
    required this.reps,
    required this.achievedAtUtc,
    this.previousBestWeightKg,
  });

  double? get deltaKg =>
      previousBestWeightKg == null ? null : weightKg - previousBestWeightKg!;

  factory PersonalRecord.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return PersonalRecord(
      exerciseId: map['exerciseId'] as String,
      exerciseName: map['exerciseName'] as String? ?? '',
      weightKg: (map['weightKg'] as num?)?.toDouble() ?? 0,
      reps: map['reps'] as int? ?? 0,
      achievedAtUtc: DateTime.parse(map['achievedAtUtc'] as String),
      previousBestWeightKg: (map['previousBestWeightKg'] as num?)?.toDouble(),
    );
  }
}

/// An exercise the account has logged at least one set for. Mirrors
/// `Silen.Common.Dtos.TrackedExerciseDto`.
class TrackedExercise {
  final String exerciseId;
  final String exerciseName;
  final int sessionCount;
  final DateTime lastTrainedAtUtc;

  const TrackedExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.sessionCount,
    required this.lastTrainedAtUtc,
  });

  factory TrackedExercise.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return TrackedExercise(
      exerciseId: map['exerciseId'] as String,
      exerciseName: map['exerciseName'] as String? ?? '',
      sessionCount: map['sessionCount'] as int? ?? 0,
      lastTrainedAtUtc: DateTime.parse(map['lastTrainedAtUtc'] as String),
    );
  }
}

/// One session's worth of a single exercise. Mirrors
/// `Silen.Common.Dtos.ExerciseProgressPointDto`.
class ExerciseProgressPoint {
  final DateTime date;
  final double topWeightKg;
  final int topSetReps;
  final double estimatedOneRmKg;
  final double totalVolumeKg;
  final int totalReps;
  final int setCount;

  const ExerciseProgressPoint({
    required this.date,
    required this.topWeightKg,
    required this.topSetReps,
    required this.estimatedOneRmKg,
    required this.totalVolumeKg,
    required this.totalReps,
    required this.setCount,
  });

  factory ExerciseProgressPoint.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return ExerciseProgressPoint(
      date: DateTime.parse(map['date'] as String),
      topWeightKg: (map['topWeightKg'] as num?)?.toDouble() ?? 0,
      topSetReps: map['topSetReps'] as int? ?? 0,
      estimatedOneRmKg: (map['estimatedOneRmKg'] as num?)?.toDouble() ?? 0,
      totalVolumeKg: (map['totalVolumeKg'] as num?)?.toDouble() ?? 0,
      totalReps: map['totalReps'] as int? ?? 0,
      setCount: map['setCount'] as int? ?? 0,
    );
  }
}

/// Per-session history of one exercise, oldest first. Mirrors
/// `Silen.Common.Dtos.ExerciseProgressDto`.
class ExerciseProgress {
  final String exerciseId;
  final int days;
  final List<ExerciseProgressPoint> points;

  const ExerciseProgress({
    required this.exerciseId,
    required this.days,
    required this.points,
  });

  factory ExerciseProgress.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return ExerciseProgress(
      exerciseId: map['exerciseId'] as String,
      days: map['days'] as int? ?? 0,
      points: (map['points'] as List<dynamic>? ?? [])
          .map((e) => ExerciseProgressPoint.fromJson(e))
          .toList(),
    );
  }
}

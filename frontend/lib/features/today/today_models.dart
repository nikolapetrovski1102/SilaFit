/// Mirrors `Silen.Common.Dtos.TodayDtos` exactly, field for field.
class TodayDashboard {
  final TodaySession session;
  final List<TargetExercise> targetExercises;
  final int hydrationTotalMl;
  final int hydrationTargetMl;
  final double? latestWeightKg;
  final double? weightDeltaKg;
  final int currentStreakDays;
  final int weeklyCompliancePercent;
  final List<WeekDayStatus> weekStatuses;
  final ActiveSplit? activeSplit;

  const TodayDashboard({
    required this.session,
    required this.targetExercises,
    required this.hydrationTotalMl,
    required this.hydrationTargetMl,
    this.latestWeightKg,
    this.weightDeltaKg,
    required this.currentStreakDays,
    required this.weeklyCompliancePercent,
    required this.weekStatuses,
    this.activeSplit,
  });

  factory TodayDashboard.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return TodayDashboard(
      session: TodaySession.fromJson(map['session']),
      targetExercises: (map['targetExercises'] as List<dynamic>? ?? [])
          .map((e) => TargetExercise.fromJson(e))
          .toList(),
      hydrationTotalMl: map['hydrationTotalMl'] as int? ?? 0,
      hydrationTargetMl: map['hydrationTargetMl'] as int? ?? 0,
      latestWeightKg: (map['latestWeightKg'] as num?)?.toDouble(),
      weightDeltaKg: (map['weightDeltaKg'] as num?)?.toDouble(),
      currentStreakDays: map['currentStreakDays'] as int? ?? 0,
      weeklyCompliancePercent: map['weeklyCompliancePercent'] as int? ?? 0,
      weekStatuses: (map['weekStatuses'] as List<dynamic>? ?? [])
          .map((e) => WeekDayStatus.fromJson(e))
          .toList(),
      activeSplit: map['activeSplit'] == null
          ? null
          : ActiveSplit.fromJson(map['activeSplit']),
    );
  }

  TodayDashboard copyWith(
          {int? hydrationTotalMl,
          double? latestWeightKg,
          double? weightDeltaKg}) =>
      TodayDashboard(
        session: session,
        targetExercises: targetExercises,
        hydrationTotalMl: hydrationTotalMl ?? this.hydrationTotalMl,
        hydrationTargetMl: hydrationTargetMl,
        latestWeightKg: latestWeightKg ?? this.latestWeightKg,
        weightDeltaKg: weightDeltaKg ?? this.weightDeltaKg,
        currentStreakDays: currentStreakDays,
        weeklyCompliancePercent: weeklyCompliancePercent,
        weekStatuses: weekStatuses,
        activeSplit: activeSplit,
      );
}

class ActiveSplit {
  final String splitId;
  final String? name;
  final int? durationDays;
  final DateTime activatedAtUtc;

  const ActiveSplit({
    required this.splitId,
    this.name,
    this.durationDays,
    required this.activatedAtUtc,
  });

  factory ActiveSplit.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return ActiveSplit(
      splitId: map['splitId'] as String,
      name: map['name'] as String?,
      durationDays: map['durationDays'] as int?,
      activatedAtUtc: DateTime.parse(map['activatedAtUtc'] as String),
    );
  }
}

class TodaySession {
  final String? workoutSessionId;
  final String status; // Scheduled | Completed | Missed | ActiveRest
  final String? title;
  final String? focusLabel;
  final int? estimatedMinutes;
  final bool isRestDay;

  const TodaySession({
    this.workoutSessionId,
    required this.status,
    this.title,
    this.focusLabel,
    this.estimatedMinutes,
    required this.isRestDay,
  });

  factory TodaySession.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return TodaySession(
      workoutSessionId: map['workoutSessionId'] as String?,
      status: map['status'] as String? ?? 'Scheduled',
      title: map['title'] as String?,
      focusLabel: map['focusLabel'] as String?,
      estimatedMinutes: map['estimatedMinutes'] as int?,
      isRestDay: map['isRestDay'] as bool? ?? false,
    );
  }
}

class TargetExercise {
  final String exerciseId;
  final String name;
  final String muscleGroup;
  final String? equipmentType;
  final String? demoVideoUrl;
  final int targetSets;
  final int targetRepsLow;
  final int targetRepsHigh;

  const TargetExercise({
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    this.equipmentType,
    this.demoVideoUrl,
    required this.targetSets,
    required this.targetRepsLow,
    required this.targetRepsHigh,
  });

  factory TargetExercise.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return TargetExercise(
      exerciseId: map['exerciseId'] as String,
      name: map['name'] as String? ?? '',
      muscleGroup: map['muscleGroup'] as String? ?? '',
      equipmentType: map['equipmentType'] as String?,
      demoVideoUrl: map['demoVideoUrl'] as String?,
      targetSets: map['targetSets'] as int? ?? 0,
      targetRepsLow: map['targetRepsLow'] as int? ?? 0,
      targetRepsHigh: map['targetRepsHigh'] as int? ?? 0,
    );
  }
}

class WeekDayStatus {
  final DateTime date;
  final String status;

  const WeekDayStatus({required this.date, required this.status});

  factory WeekDayStatus.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return WeekDayStatus(
        date: DateTime.parse(map['date'] as String),
        status: map['status'] as String? ?? 'Scheduled');
  }
}

class BodyweightLogResult {
  final double latestWeightKg;
  final double? deltaKg;

  const BodyweightLogResult({required this.latestWeightKg, this.deltaKg});

  factory BodyweightLogResult.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return BodyweightLogResult(
      latestWeightKg: (map['latestWeightKg'] as num).toDouble(),
      deltaKg: (map['deltaKg'] as num?)?.toDouble(),
    );
  }
}

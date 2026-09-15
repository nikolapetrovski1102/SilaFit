/// English month name for `month` (1-12), or a neutral fallback for a malformed
/// value - shared by [MonthlyAnalytics.periodLabel] and the recap screen header.
String monthLabel(int year, int month) {
  if (month < 1 || month > 12) return 'Monthly Recap';
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${names[month - 1]} $year';
}

/// The shared shape both the monthly (Pro) and weekly (Advanced) recap screens
/// render. Monthly and weekly reports differ only in their period metadata and
/// their forward-looking copy, so the slideshow works against this interface
/// and the two concrete models supply the period-specific bits.
abstract class AnalyticsRecap {
  List<MonthlyExercise> get exercises;
  int? get missedWorkoutDays;
  int? get daysOverCalorieTarget;
  int? get totalCaloriesOverTarget;
  int? get calorieTarget;
  MonthlyAnalyticsSummary get summary;
  List<String> get strengths;
  List<AnalyticsImprovement> get improvements;
  String get focusText;
  DateTime get generatedAtUtc;

  /// Human label for the covered period, e.g. "August 2026" or
  /// "Week 37 · Sep 7 – Sep 13, 2026".
  String get periodLabel;

  /// True for the weekly (Advanced) recap: month copy becomes week copy and the
  /// meal/split recommendation slides are appended after the standard six.
  bool get isWeekly;
}

/// Mirrors `Silen.Common.Dtos.AnalyticsDtos.MonthlyAnalyticsDto`.
class MonthlyAnalytics implements AnalyticsRecap {
  @override
  final List<MonthlyExercise> exercises;
  @override
  final int? missedWorkoutDays;
  @override
  final int? daysOverCalorieTarget;
  @override
  final int? totalCaloriesOverTarget;
  @override
  final int? calorieTarget;
  final int year;
  final int month;
  @override
  final MonthlyAnalyticsSummary summary;
  @override
  final List<String> strengths;
  @override
  final List<AnalyticsImprovement> improvements;
  final String focusForNextMonth;
  @override
  final DateTime generatedAtUtc;

  @override
  bool get isWeekly => false;

  @override
  String get focusText => focusForNextMonth;

  @override
  String get periodLabel => monthLabel(year, month);

  const MonthlyAnalytics({
    this.exercises = const [],
    this.missedWorkoutDays,
    this.daysOverCalorieTarget,
    this.totalCaloriesOverTarget,
    this.calorieTarget,
    required this.year,
    required this.month,
    required this.summary,
    required this.strengths,
    required this.improvements,
    required this.focusForNextMonth,
    required this.generatedAtUtc,
  });

  factory MonthlyAnalytics.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return MonthlyAnalytics(
      exercises: (map['exercises'] as List<dynamic>? ?? [])
          .map((e) => MonthlyExercise.fromJson(e as Map<String, dynamic>))
          .toList(),
      missedWorkoutDays: map['missedWorkoutDays'] as int?,
      daysOverCalorieTarget: map['daysOverCalorieTarget'] as int?,
      totalCaloriesOverTarget: map['totalCaloriesOverTarget'] as int?,
      calorieTarget: map['calorieTarget'] as int?,
      year: map['year'] as int? ?? 0,
      month: map['month'] as int? ?? 0,
      summary: MonthlyAnalyticsSummary.fromJson(map['summary']),
      strengths: (map['strengths'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      improvements: (map['improvements'] as List<dynamic>? ?? [])
          .map((e) => AnalyticsImprovement.fromJson(e))
          .toList(),
      focusForNextMonth: map['focusForNextMonth'] as String? ?? '',
      generatedAtUtc:
          DateTime.tryParse(map['generatedAtUtc'] as String? ?? '') ??
              DateTime.now(),
    );
  }
}

/// Real numbers from logged data - never AI-written.
class MonthlyAnalyticsSummary {
  final int completedSessions;
  final int scheduledSessions;
  final double totalTonnageKg;
  final double avgRpe;
  final int currentStreakDays;
  final int weeklyCompliancePercent;
  final double? startWeightKg;
  final double? endWeightKg;
  final int loggedMealDays;
  final int totalDaysInRange;

  const MonthlyAnalyticsSummary({
    required this.completedSessions,
    required this.scheduledSessions,
    required this.totalTonnageKg,
    required this.avgRpe,
    required this.currentStreakDays,
    required this.weeklyCompliancePercent,
    this.startWeightKg,
    this.endWeightKg,
    required this.loggedMealDays,
    required this.totalDaysInRange,
  });

  factory MonthlyAnalyticsSummary.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>? ?? const {};
    return MonthlyAnalyticsSummary(
      completedSessions: map['completedSessions'] as int? ?? 0,
      scheduledSessions: map['scheduledSessions'] as int? ?? 0,
      totalTonnageKg: (map['totalTonnageKg'] as num?)?.toDouble() ?? 0,
      avgRpe: (map['avgRpe'] as num?)?.toDouble() ?? 0,
      currentStreakDays: map['currentStreakDays'] as int? ?? 0,
      weeklyCompliancePercent: map['weeklyCompliancePercent'] as int? ?? 0,
      startWeightKg: (map['startWeightKg'] as num?)?.toDouble(),
      endWeightKg: (map['endWeightKg'] as num?)?.toDouble(),
      loggedMealDays: map['loggedMealDays'] as int? ?? 0,
      totalDaysInRange: map['totalDaysInRange'] as int? ?? 0,
    );
  }
}

class AnalyticsImprovement {
  final String area;
  final String recommendation;
  final String priority;

  const AnalyticsImprovement({
    required this.area,
    required this.recommendation,
    required this.priority,
  });

  factory AnalyticsImprovement.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return AnalyticsImprovement(
      area: map['area'] as String? ?? '',
      recommendation: map['recommendation'] as String? ?? '',
      priority: map['priority'] as String? ?? 'Medium',
    );
  }
}

class MonthlyExercise {
  final String exerciseId;
  final String exerciseName;
  final double recordWeightKg;
  final List<MonthlyExercisePoint> points;
  const MonthlyExercise(
      {required this.exerciseId,
      required this.exerciseName,
      required this.recordWeightKg,
      required this.points});

  factory MonthlyExercise.fromJson(Map<String, dynamic> map) => MonthlyExercise(
        exerciseId: map['exerciseId'] as String,
        exerciseName: map['exerciseName'] as String,
        recordWeightKg: (map['recordWeightKg'] as num).toDouble(),
        points: (map['points'] as List<dynamic>)
            .map(
                (p) => MonthlyExercisePoint.fromJson(p as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.dateUtc.compareTo(b.dateUtc)),
      );

  // A heavier set with fewer reps is a load change, not a demonstrated gain.
  bool get improved =>
      points.length >= 2 &&
      ((points.last.weightKg > points.first.weightKg &&
              points.last.reps >= points.first.reps) ||
          (points.last.weightKg == points.first.weightKg &&
              points.last.reps > points.first.reps));
  bool get steadyLoad =>
      points.length >= 3 &&
      points.every((p) => p.weightKg == points.first.weightKg);
}

class MonthlyExercisePoint {
  final DateTime dateUtc;
  final double weightKg;
  final int reps;
  final double? sessionRpe;
  const MonthlyExercisePoint(
      {required this.dateUtc,
      required this.weightKg,
      required this.reps,
      this.sessionRpe});
  factory MonthlyExercisePoint.fromJson(Map<String, dynamic> map) =>
      MonthlyExercisePoint(
        dateUtc: DateTime.parse(map['dateUtc'] as String),
        weightKg: (map['weightKg'] as num).toDouble(),
        reps: map['reps'] as int,
        sessionRpe: (map['sessionRpe'] as num?)?.toDouble(),
      );
}

/// Mirrors `Silen.Common.Dtos.AnalyticsDtos.WeeklyAnalyticsDto` - the ADVANCED
/// weekly counterpart of [MonthlyAnalytics], with the same real-data summary
/// and AI copy but scoped to one ISO week.
class WeeklyAnalytics implements AnalyticsRecap {
  @override
  final List<MonthlyExercise> exercises;
  @override
  final int? missedWorkoutDays;
  @override
  final int? daysOverCalorieTarget;
  @override
  final int? totalCaloriesOverTarget;
  @override
  final int? calorieTarget;
  final int year;
  final int weekNumber;
  final DateTime weekStartUtc;
  final DateTime weekEndUtc;
  @override
  final MonthlyAnalyticsSummary summary;
  @override
  final List<String> strengths;
  @override
  final List<AnalyticsImprovement> improvements;
  final String focusForNextWeek;
  @override
  final DateTime generatedAtUtc;

  @override
  bool get isWeekly => true;

  @override
  String get focusText => focusForNextWeek;

  @override
  String get periodLabel =>
      'Week $weekNumber · ${_shortDate(weekStartUtc)} – ${_shortDate(weekEndUtc)}, $year';

  const WeeklyAnalytics({
    this.exercises = const [],
    this.missedWorkoutDays,
    this.daysOverCalorieTarget,
    this.totalCaloriesOverTarget,
    this.calorieTarget,
    required this.year,
    required this.weekNumber,
    required this.weekStartUtc,
    required this.weekEndUtc,
    required this.summary,
    required this.strengths,
    required this.improvements,
    required this.focusForNextWeek,
    required this.generatedAtUtc,
  });

  factory WeeklyAnalytics.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    final weekStart = DateTime.tryParse(map['weekStartUtc'] as String? ?? '') ??
        DateTime.now();
    final weekEnd =
        DateTime.tryParse(map['weekEndUtc'] as String? ?? '') ?? weekStart;
    return WeeklyAnalytics(
      exercises: (map['exercises'] as List<dynamic>? ?? [])
          .map((e) => MonthlyExercise.fromJson(e as Map<String, dynamic>))
          .toList(),
      missedWorkoutDays: map['missedWorkoutDays'] as int?,
      daysOverCalorieTarget: map['daysOverCalorieTarget'] as int?,
      totalCaloriesOverTarget: map['totalCaloriesOverTarget'] as int?,
      calorieTarget: map['calorieTarget'] as int?,
      year: map['year'] as int? ?? 0,
      weekNumber: map['weekNumber'] as int? ?? 0,
      weekStartUtc: weekStart,
      weekEndUtc: weekEnd,
      summary: MonthlyAnalyticsSummary.fromJson(map['summary']),
      strengths: (map['strengths'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      improvements: (map['improvements'] as List<dynamic>? ?? [])
          .map((e) => AnalyticsImprovement.fromJson(e))
          .toList(),
      focusForNextWeek: map['focusForNextWeek'] as String? ?? '',
      generatedAtUtc:
          DateTime.tryParse(map['generatedAtUtc'] as String? ?? '') ??
              DateTime.now(),
    );
  }
}

String _shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = date.month >= 1 && date.month <= 12
      ? months[date.month - 1]
      : '${date.month}';
  return '$month ${date.day}';
}

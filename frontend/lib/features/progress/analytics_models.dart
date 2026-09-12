/// Mirrors `Silen.Common.Dtos.AnalyticsDtos`.
class MonthlyAnalytics {
  final int year;
  final int month;
  final MonthlyAnalyticsSummary summary;
  final List<String> strengths;
  final List<AnalyticsImprovement> improvements;
  final String focusForNextMonth;
  final DateTime generatedAtUtc;

  const MonthlyAnalytics({
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
      generatedAtUtc: DateTime.tryParse(map['generatedAtUtc'] as String? ?? '') ??
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

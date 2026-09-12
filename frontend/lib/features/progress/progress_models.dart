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

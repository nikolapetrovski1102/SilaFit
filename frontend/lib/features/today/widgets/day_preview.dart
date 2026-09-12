import '../../splits/splits_models.dart';
import '../today_models.dart';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// Looks up which day of the active split's rotation lands on [date], given
/// when the split was activated - the same `DATEDIFF(...) % DurationDays`
/// cycle the backend uses to resolve *today's* scheduled session
/// (`usp_WorkoutSession_GetTodayScheduled`), just evaluated for an arbitrary
/// date so the strip can preview days that haven't happened yet.
SplitDay? resolveSplitDay(DateTime date, ActiveSplit split, SplitDetail detail) {
  final duration = split.durationDays;
  if (duration == null || duration <= 0) return null;
  final activated = dateOnly(split.activatedAtUtc);
  final target = dateOnly(date);
  final cycleLength = duration;
  final diff = target.difference(activated).inDays;
  final cycleIndex = ((diff % cycleLength) + cycleLength) % cycleLength;
  for (final entry in detail.days) {
    if (entry.day.dayIndex == cycleIndex) return entry.day;
  }
  return null;
}

/// Everything Home's hero session card needs to render whichever day is
/// currently centered in `DayScrollStrip` - today's real, completable
/// session; a past day's logged outcome; or a preview of what the active
/// split has scheduled for a day that hasn't happened yet.
class DayPreview {
  final DateTime date;
  final bool isToday;
  final String status; // Scheduled | Completed | Missed | ActiveRest
  final String? title;
  final String? focusLabel;
  final int? estimatedMinutes;
  final bool isRestDay;

  /// Only set when [isToday] - the one day with a real, completable session.
  final String? workoutSessionId;
  final List<TargetExercise> targetExercises;

  const DayPreview({
    required this.date,
    required this.isToday,
    required this.status,
    this.title,
    this.focusLabel,
    this.estimatedMinutes,
    required this.isRestDay,
    this.workoutSessionId,
    this.targetExercises = const [],
  });

  factory DayPreview.today(TodayDashboard dashboard) {
    final session = dashboard.session;
    return DayPreview(
      date: dateOnly(DateTime.now()),
      isToday: true,
      status: session.status,
      title: session.title,
      focusLabel: session.focusLabel,
      estimatedMinutes: session.estimatedMinutes,
      isRestDay: session.isRestDay,
      workoutSessionId: session.workoutSessionId,
      targetExercises: dashboard.targetExercises,
    );
  }

  /// Resolves any other date from whatever's known about it: a logged
  /// status from this week/history ([knownStatus]), plus the active split's
  /// rotation ([splitDetail]) for the title/focus/duration a scheduled or
  /// upcoming day carries. Falls back to a bare "Scheduled" placeholder when
  /// neither source has anything - no split active, or history for that day
  /// hasn't loaded yet. [date] landing on today always defers to
  /// [DayPreview.today] instead, so a freshly-completed workout shows up
  /// immediately rather than through whatever status was known when the day
  /// was first centered.
  factory DayPreview.resolve({
    required DateTime date,
    required TodayDashboard dashboard,
    WeekDayStatus? knownStatus,
    SplitDetail? splitDetail,
  }) {
    if (isSameCalendarDay(date, DateTime.now())) return DayPreview.today(dashboard);

    final activeSplit = dashboard.activeSplit;
    final splitDay = activeSplit != null && splitDetail != null
        ? resolveSplitDay(date, activeSplit, splitDetail)
        : null;

    final isRest = knownStatus?.status == 'ActiveRest' ||
        (knownStatus == null && (splitDay?.isRestDay ?? false));

    return DayPreview(
      date: dateOnly(date),
      isToday: false,
      status: knownStatus?.status ?? 'Scheduled',
      title: splitDay?.title,
      focusLabel: splitDay?.focusLabel,
      estimatedMinutes: splitDay?.estimatedMinutes,
      isRestDay: isRest,
    );
  }
}

import '../../splits/splits_models.dart';
import '../today_models.dart';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// The Monday of the week [activatedAtUtc] falls in. Every split's rotation
/// is anchored here so its first day always lands on a Monday - activating
/// mid-week picks up at that weekday's slot. Mirrors `@AnchorDate` in
/// `usp_WorkoutSession_GetTodayScheduled`.
DateTime splitCycleAnchor(DateTime activatedAtUtc) {
  final activated = dateOnly(activatedAtUtc);
  return activated
      .subtract(Duration(days: activated.weekday - DateTime.monday));
}

/// Looks up which day of the active split's rotation lands on [date], given
/// when the split was activated - the same cycle the backend uses to resolve
/// *today's* scheduled session (`usp_WorkoutSession_GetTodayScheduled`),
/// just evaluated for an arbitrary date so the strip can preview days that
/// haven't happened yet. The rotation runs indefinitely - it keeps repeating
/// until the user activates a different split.
///
/// The rotation is whole weeks long ([splitCycleLength]) and anchored to a
/// Monday, so Day 1 always falls on a Monday. The day is picked by its stored
/// `dayIndex` (slot `i` is Day `i + 1`), so a gap in the numbering - Day 1,
/// Day 2, Day 4 - rests on the missing day instead of pulling the later days
/// forward, and any slot with no authored day resolves to [implicitRestDay].
SplitDayWithExercises? resolveSplitDayWithExercises(
    DateTime date, ActiveSplit split, SplitDetail detail) {
  final duration = split.durationDays;
  if (duration == null || duration <= 0) return null;
  final anchor = splitCycleAnchor(split.activatedAtUtc);
  final target = dateOnly(date);
  final ordered = daysWithImplicitRest(detail.days, duration);
  final cycleLength = ordered.length;
  // Compared as UTC dates: local midnights are 23h apart across a DST
  // spring-forward, which would make `inDays` come up a day short.
  final diff = DateTime.utc(target.year, target.month, target.day)
      .difference(DateTime.utc(anchor.year, anchor.month, anchor.day))
      .inDays;
  final cycleIndex = ((diff % cycleLength) + cycleLength) % cycleLength;
  return ordered[cycleIndex];
}

SplitDay? resolveSplitDay(
        DateTime date, ActiveSplit split, SplitDetail detail) =>
    resolveSplitDayWithExercises(date, split, detail)?.day;

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
  final List<SplitDayExercise> scheduledExercises;

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
    this.scheduledExercises = const [],
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
    if (isSameCalendarDay(date, DateTime.now())) {
      return DayPreview.today(dashboard);
    }

    final activeSplit = dashboard.activeSplit;
    final splitDayWithExercises = activeSplit != null && splitDetail != null
        ? resolveSplitDayWithExercises(date, activeSplit, splitDetail)
        : null;
    final splitDay = splitDayWithExercises?.day;

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
      scheduledExercises: splitDayWithExercises?.exercises ?? const [],
    );
  }
}

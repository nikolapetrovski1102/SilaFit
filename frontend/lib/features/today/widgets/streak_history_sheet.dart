import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/state/resource_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/section_eyebrow.dart';
import '../../../core/widgets/skeleton.dart';
import '../../plans/plans_repository.dart';
import '../../progress/progress_models.dart';
import '../../progress/progress_repository.dart';
import 'set_history_screen.dart';
import 'day_preview.dart';

/// Opens the streak history sheet - tapped from the streak badge on Home.
/// Shows the last 12 weeks of sessions as a small calendar so the user can
/// see when they trained, when they rested, and when they missed a day. A
/// rest day reads the same as a completed one here since it does not break
/// the streak. A completed day opens that day's sets ([SetHistoryScreen]) -
/// the last 14 days on Free, the last 30 on Pro/Advanced.
Future<void> showStreakHistorySheet(
  BuildContext context, {
  required int currentStreakDays,
  required int weeklyCompliancePercent,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (_) => StreakHistorySheet(
      currentStreakDays: currentStreakDays,
      weeklyCompliancePercent: weeklyCompliancePercent,
    ),
  );
}

class StreakHistorySheet extends StatefulWidget {
  final int currentStreakDays;
  final int weeklyCompliancePercent;

  const StreakHistorySheet(
      {super.key,
      required this.currentStreakDays,
      required this.weeklyCompliancePercent});

  @override
  State<StreakHistorySheet> createState() => _StreakHistorySheetState();
}

class _StreakHistorySheetState extends State<StreakHistorySheet> {
  // 84 days = 12 full weeks, enough history to show a real pattern without
  // asking the API for the user's whole lifetime of sessions.
  static const _historyDays = 84;

  // How far back a completed day opens its set history. Free's window is
  // also enforced server-side (`TodayService.FreeWorkoutHistoryDays`).
  static const _freeHistoryDays = 14;
  static const _paidHistoryDays = 30;

  ResourceState<ProgressOverview> _state = const ResourceState.loading();

  // Null until fetched (or if that fails) - treated as Free meanwhile, so
  // nothing is ever offered that the server would then refuse.
  String? _planCode;

  bool get _isPaid => _planCode == 'PRO' || _planCode == 'ADVANCED';

  @override
  void initState() {
    super.initState();
    _load();
    _loadPlanCode();
  }

  Future<void> _loadPlanCode() async {
    try {
      final plan = await context.read<PlansRepository>().getActivePlanCode();
      if (!mounted) return;
      setState(() => _planCode = plan);
    } catch (_) {
      // Best-effort - stays on the Free window.
    }
  }

  void _openDay(HeatmapDay day, {required bool locked}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SetHistoryScreen(date: day.date, locked: locked),
    ));
  }

  Future<void> _load() async {
    setState(() => _state = const ResourceState.loading());
    try {
      final overview = await context
          .read<ProgressRepository>()
          .getOverview(days: _historyDays);
      if (!mounted) return;
      setState(() => _state = ResourceState.data(overview));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _state = ResourceState.error(e.userMessage));
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _state = const ResourceState.error(ApiException.genericMessage));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
            AppSpacing.marginMobile, AppSpacing.marginMobile, AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department_rounded,
                    color: AppColors.accent, size: 26),
                const SizedBox(width: AppSpacing.xs),
                Text('${widget.currentStreakDays} day streak',
                    style: AppTypography.headlineMd),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'This week is ${widget.weeklyCompliancePercent} percent complete.',
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionEyebrow('Consistency history'),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              _isPaid
                  ? 'Tap a completed day from the last $_paidHistoryDays days to see its sets.'
                  : 'Tap a completed day from the last $_freeHistoryDays days to see its sets. Pro shows the full month.',
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: SingleChildScrollView(
                child: ResourceBuilder<ProgressOverview>(
                  state: _state,
                  onRetry: _load,
                  skeleton: const SkeletonGrid(),
                  builder: (context, overview) => _HistoryGrid(
                    days: overview.heatmap,
                    isPaid: _isPaid,
                    windowDays: _isPaid ? _paidHistoryDays : _freeHistoryDays,
                    paidWindowDays: _paidHistoryDays,
                    onOpenDay: _openDay,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                _LegendItem(status: 'Completed', label: 'Completed'),
                _LegendItem(status: 'ActiveRest', label: 'Rest day'),
                _LegendItem(status: 'Missed', label: 'Missed'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String status;
  final String label;

  const _LegendItem({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: AppColors.forSessionStatus(status),
              shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(label,
            style: AppTypography.labelSm
                .copyWith(color: AppColors.onSurfaceVariant)),
      ],
    );
  }
}

/// Weekday header row, then one row per week (most recent first), each a
/// dot per day colored by status. A blank slot is a day the program had no
/// session for at all (before the user started, or outside the split), kept
/// visually distinct from an actual missed session.
class _HistoryGrid extends StatelessWidget {
  final List<HeatmapDay> days;
  final bool isPaid;
  final int windowDays;
  final int paidWindowDays;
  final void Function(HeatmapDay day, {required bool locked}) onOpenDay;

  const _HistoryGrid({
    required this.days,
    required this.isPaid,
    required this.windowDays,
    required this.paidWindowDays,
    required this.onOpenDay,
  });

  /// What tapping [day] does: opens it, opens it behind the Pro lock (a
  /// Free user past their 14 days but inside the paid month), or nothing.
  _DayAccess _accessFor(HeatmapDay? day) {
    if (day == null || day.status != 'Completed') return _DayAccess.none;
    final today = DateUtils.dateOnly(DateTime.now());
    final age = today.difference(DateUtils.dateOnly(day.date)).inDays;
    if (age < 0) return _DayAccess.none;
    if (age < windowDays) return _DayAccess.open;
    if (!isPaid && age < paidWindowDays) return _DayAccess.locked;
    return _DayAccess.none;
  }

  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  List<List<HeatmapDay?>> _groupByWeek() {
    final sorted = [...days]..sort((a, b) => a.date.compareTo(b.date));
    final weeks = <List<HeatmapDay?>>[];
    List<HeatmapDay?>? current;
    DateTime? weekStart;
    for (final day in sorted) {
      final start = addDays(day.date, DateTime.monday - day.date.weekday);
      if (weekStart == null ||
          start.year != weekStart.year ||
          start.month != weekStart.month ||
          start.day != weekStart.day) {
        current = List<HeatmapDay?>.filled(7, null);
        weeks.add(current);
        weekStart = start;
      }
      current![day.date.weekday - 1] = day;
    }
    return weeks;
  }

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Text('No sessions logged yet.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant)),
      );
    }

    final weeks = _groupByWeek();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final letter in _weekdayLetters)
              Expanded(
                child: Center(
                  child: Text(letter,
                      style: AppTypography.labelCaps.copyWith(fontSize: 10)),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final week in weeks.reversed)
          Row(
            children: [
              for (final day in week) Expanded(child: _buildCell(day)),
            ],
          ),
      ],
    );
  }

  Widget _buildCell(HeatmapDay? day) {
    final access = _accessFor(day);
    final dot = _HistoryDot(day: day, access: access);
    if (access == _DayAccess.none) {
      return SizedBox(height: 36, child: Center(child: dot));
    }
    return Semantics(
      button: true,
      label: access == _DayAccess.locked
          ? 'Completed day, history requires Pro'
          : 'View sets for this day',
      child: InkResponse(
        radius: 20,
        onTap: () => onOpenDay(day!, locked: access == _DayAccess.locked),
        child: SizedBox(height: 36, child: Center(child: dot)),
      ),
    );
  }
}

enum _DayAccess { open, locked, none }

class _HistoryDot extends StatelessWidget {
  final HeatmapDay? day;
  final _DayAccess access;

  const _HistoryDot({required this.day, this.access = _DayAccess.none});

  @override
  Widget build(BuildContext context) {
    final entry = day;
    if (entry == null) {
      return Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.outlineVariant, width: 1),
        ),
      );
    }

    final isFuture = entry.date.isAfter(DateTime.now());
    if (isFuture) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.outlineVariant, width: 1),
        ),
      );
    }

    IconData? icon;
    switch (entry.status) {
      case 'Completed':
        icon = Icons.check_rounded;
      case 'ActiveRest':
        icon = Icons.nightlight_round;
      case 'Missed':
        icon = Icons.close_rounded;
    }

    // Days that open their sets get a larger dot with an accent ring so
    // they read as tappable; a Free user's locked day shows a lock instead
    // of the check.
    final tappable = access != _DayAccess.none;
    final size = tappable ? 24.0 : 18.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.forSessionStatus(entry.status)
            .withValues(alpha: access == _DayAccess.locked ? 0.45 : 1),
        shape: BoxShape.circle,
        border: access == _DayAccess.open
            ? Border.all(
                color: AppColors.accent.withValues(alpha: 0.35),
                width: 3,
                strokeAlign: BorderSide.strokeAlignOutside)
            : null,
      ),
      child: access == _DayAccess.locked
          ? Icon(Icons.lock_rounded, size: 12, color: AppColors.background)
          : icon == null
              ? null
              : Icon(icon,
                  size: tappable ? 14 : 11, color: AppColors.background),
    );
  }
}

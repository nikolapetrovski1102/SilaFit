import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../progress/progress_repository.dart';
import '../../splits/splits_models.dart';
import '../today_models.dart';
import 'day_preview.dart';

typedef DaySelectionCallback = void Function(
    DateTime date, WeekDayStatus? status);

/// Horizontally scrollable day picker - a flat strip of fixed-size day
/// pills (no wheel-picker bulge/fade tied to scroll position) centered on
/// today by default, spanning roughly two months of history and two weeks
/// into the future. Whichever day sits in the middle is the "active" one:
/// it carries the accent ring and the hanging connector line, and scrolling
/// to a new center - by drag or by tapping a day to bring it to the middle -
/// reports that day up via [onSelect] once the scroll settles, so Home's
/// hero session card can grow out of it (today's real session, a past
/// day's logged outcome, or a preview of what the active split has
/// scheduled for a day that hasn't happened yet).
///
/// The only animation in the strip is `_focusOn`'s glide to a tapped day -
/// a drag settling on a new center just snaps the ring/connector to it,
/// same as the pill sizes themselves, which never change.
///
/// Deliberately fixed-height regardless of what's centered - this whole
/// strip lives inside Home's `FitHeight`, and only the *committed* selection
/// (passed up to the screen, which folds it into `measureKey`) should ever
/// trigger a remeasure. Which day carries the ring (`_liveIndex`) stays
/// local state so a fling never fights with a mid-flight rescale.
class DayScrollStrip extends StatefulWidget {
  final List<WeekDayStatus> weekStatuses;
  final ActiveSplit? activeSplit;
  final SplitDetail? splitDetail;
  final double scale;
  final DaySelectionCallback onSelect;

  const DayScrollStrip({
    super.key,
    required this.weekStatuses,
    required this.activeSplit,
    required this.splitDetail,
    required this.scale,
    required this.onSelect,
  });

  @override
  State<DayScrollStrip> createState() => _DayScrollStripState();
}

class _DayScrollStripState extends State<DayScrollStrip> {
  // ~2 months back - enough to feel like real history to scroll through
  // without asking the API for the user's whole lifetime of sessions.
  static const _historyDays = 60;
  // Not too far - a preview of the split's rotation, not a calendar.
  static const _futureDays = 14;

  final _scrollController = ScrollController();
  final Map<String, WeekDayStatus> _knownByKey = {};
  List<WeekDayStatus> _days = const [];
  int _liveIndex = 0;
  int? _committedIndex;

  double get _itemExtent =>
      DayOval.width(widget.scale) + AppSpacing.sm * widget.scale;

  @override
  void initState() {
    super.initState();
    for (final d in widget.weekStatuses) {
      _knownByKey[dayKey(d.date)] = d;
    }
    _days = _computeDays();
    _liveIndex = _committedIndex = _todayIndex();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnToday());
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant DayScrollStrip old) {
    super.didUpdateWidget(old);
    if (old.weekStatuses != widget.weekStatuses) {
      for (final d in widget.weekStatuses) {
        _knownByKey[dayKey(d.date)] = d;
      }
    }
    if (old.weekStatuses != widget.weekStatuses ||
        old.activeSplit != widget.activeSplit ||
        old.splitDetail != widget.splitDetail) {
      setState(() => _days = _computeDays());
    }
    // `_itemExtent` is sized off `widget.scale` (it's what `DayOval` renders
    // at), and selecting a different day is exactly what changes it: a
    // different day's session card has a different natural height, so
    // `FitHeight` rescales the whole dashboard this strip lives in. The
    // controller's raw pixel offset doesn't know any of that happened, so
    // without this the centered day would drift out of center over the
    // course of that rescale.
    if (old.scale != widget.scale) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _recenterOnLiveIndex());
    }
  }

  void _recenterOnLiveIndex() {
    if (!_scrollController.hasClients || _days.isEmpty) return;
    final target = (_liveIndex * _itemExtent)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    // Jumped, not animated, but not a visible snap either: `FitHeight`
    // glides `scale` to its new target rather than cutting to it, so
    // `widget.scale` (and thus `_itemExtent`) ticks forward a little every
    // frame of that glide, re-running this correction each time. Jumping
    // straight to the recalculated target on every one of those frames is
    // what keeps the centered day pinned in place *through* the glide -
    // an eased correction of its own here would instead lag a beat behind
    // it and read as a second, competing motion.
    _scrollController.jumpTo(target);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  List<WeekDayStatus> _computeDays() {
    final today = dateOnly(DateTime.now());
    final start = today.subtract(const Duration(days: _historyDays));
    final end = today.add(const Duration(days: _futureDays));
    final split = widget.activeSplit;
    final detail = widget.splitDetail;

    final days = <WeekDayStatus>[];
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final known = _knownByKey[dayKey(d)];
      String status;
      if (known != null) {
        status = known.status;
      } else if (split != null &&
          detail != null &&
          resolveSplitDay(d, split, detail)?.isRestDay == true) {
        status = 'ActiveRest';
      } else {
        status = 'Scheduled';
      }
      days.add(WeekDayStatus(date: d, status: status));
    }
    return days;
  }

  int _todayIndex() {
    final today = dateOnly(DateTime.now());
    final index = _days.indexWhere((d) => isSameCalendarDay(d.date, today));
    return index < 0 ? 0 : index;
  }

  void _centerOnToday() {
    if (!_scrollController.hasClients) return;
    final target = _todayIndex() * _itemExtent;
    _scrollController
        .jumpTo(target.clamp(0.0, _scrollController.position.maxScrollExtent));
  }

  Future<void> _loadHistory() async {
    try {
      final overview = await context
          .read<ProgressRepository>()
          .getOverview(days: _historyDays);
      if (!mounted) return;
      for (final d in overview.heatmap) {
        _knownByKey[dayKey(d.date)] =
            WeekDayStatus(date: d.date, status: d.status);
      }
      setState(() => _days = _computeDays());
    } catch (_) {
      // Secondary affordance, not worth an error banner - the current week
      // that's already showing just stays as-is.
    }
  }

  void _onScroll() {
    if (_days.isEmpty) return;
    final index = (_scrollController.offset / _itemExtent)
        .round()
        .clamp(0, _days.length - 1);
    if (index == _liveIndex) return;
    setState(() => _liveIndex = index);
    HapticFeedback.selectionClick();
  }

  void _commitSelection() {
    if (!_scrollController.hasClients || _days.isEmpty) return;
    final index = (_scrollController.offset / _itemExtent)
        .round()
        .clamp(0, _days.length - 1);
    if (_committedIndex == index) return;
    _committedIndex = index;
    final day = _days[index];
    widget.onSelect(day.date, day);
  }

  void _focusOn(int index) {
    HapticFeedback.selectionClick();
    _scrollController.animateTo(
      (index * _itemExtent)
          .clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final itemExtent = _itemExtent;

    return SizedBox(
      // Fixed height, full stop - nothing in this strip ever grows past its
      // own box anymore, so there's no headroom to reserve and nothing for
      // the surrounding `ListView`'s viewport to clip.
      height: DayOval.heightWithConnector(scale),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sidePadding = ((constraints.maxWidth - itemExtent) / 2)
              .clamp(0.0, double.infinity);
          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification) _commitSelection();
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              // Clamping, not bouncing: hitting either end of the strip's
              // history/future window should stop dead, not rubber-band -
              // that elastic overshoot read as loose next to the otherwise
              // crisp snap-to-day motion.
              physics: _ItemSnapScrollPhysics(
                  itemExtent: () => _itemExtent,
                  parent: const ClampingScrollPhysics()),
              padding: EdgeInsets.symmetric(horizontal: sidePadding),
              itemExtent: itemExtent,
              itemCount: _days.length,
              itemBuilder: (context, index) {
                final day = _days[index];
                final isCentered = index == _liveIndex;
                // Flat, not a wheel: every pill sits at the same size and
                // opacity regardless of how far it is from center while
                // dragging - only `_focusOn` (a tap) animates anything, by
                // gliding the scroll position over to the tapped day. Which
                // pill reads as "selected" here just follows `_liveIndex`
                // straight off the scroll position, no per-frame easing.
                return Align(
                  alignment: Alignment.topCenter,
                  child: _SelectableDayOval(
                    day: day,
                    scale: scale,
                    isSelected: isCentered,
                    onTap: () => _focusOn(index),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Snaps a horizontal, fixed-[itemExtent] list to the nearest item - the
/// same detent feel as `PageScrollPhysics`, just sized to one day-oval cell
/// instead of a full viewport page. Falls through to [parent] at either end
/// so overscroll there still bounces normally.
///
/// [itemExtent] is a live getter, not a captured `double`, on purpose:
/// `Scrollable` only recreates its `ScrollPosition` when a new physics'
/// *runtimeType* chain differs from the old one, not when a field on it
/// does - so rebuilding this with a new plain `double` every time `scale`
/// changes silently keeps the stale instance (and its stale extent)
/// attached underneath. That bit a real bug: selecting a day that resizes
/// the dashboard (`FitHeight`) changed `itemExtent`, but the *attached*
/// physics kept snapping ballistic settles to the old, pre-resize extent,
/// landing the just-centered day ~17px off-center. Reading the extent
/// through a getter means even a stale instance still asks the live state
/// for the current value, so it can never go stale itself.
class _ItemSnapScrollPhysics extends ScrollPhysics {
  const _ItemSnapScrollPhysics(
      {required double Function() itemExtent, super.parent})
      : _itemExtent = itemExtent;

  final double Function() _itemExtent;
  double get itemExtent => _itemExtent();

  // Softer than a hard detent click, but still quicker than `ScrollPhysics`'s
  // own default spring (mass 0.5, stiffness 100, ratio 1.1) - that one's
  // tuned for the gentle overscroll bounce it was written for. Lower
  // stiffness than a pure "click" spring lets the settle ease in rather than
  // snapping abruptly; damping ratio 1 still keeps it free of overshoot/wobble.
  static final SpringDescription _snapSpring =
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 260, ratio: 1);

  @override
  SpringDescription get spring => _snapSpring;

  @override
  _ItemSnapScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _ItemSnapScrollPhysics(
          itemExtent: _itemExtent, parent: buildParent(ancestor));

  double _targetPixels(
      ScrollMetrics position, Tolerance tolerance, double velocity) {
    var item = position.pixels / itemExtent;
    if (velocity < -tolerance.velocity) {
      item -= 0.5;
    } else if (velocity > tolerance.velocity) {
      item += 0.5;
    }
    return item.roundToDouble() * itemExtent;
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final target = _targetPixels(position, tolerance, velocity)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) {
      return ScrollSpringSimulation(spring, position.pixels, target, velocity,
          tolerance: tolerance);
    }
    return null;
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// A day oval plus its own tap target and press feedback - the interactive
/// shell `DayScrollStrip` places around each `DayOval`.
class _SelectableDayOval extends StatefulWidget {
  final WeekDayStatus day;
  final double scale;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectableDayOval(
      {required this.day,
      required this.scale,
      required this.isSelected,
      required this.onTap});

  @override
  State<_SelectableDayOval> createState() => _SelectableDayOvalState();
}

class _SelectableDayOvalState extends State<_SelectableDayOval> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: DayOval(
            day: widget.day,
            scale: widget.scale,
            isSelected: widget.isSelected),
      ),
    );
  }
}

/// One day of the strip: an oval field carrying both the weekday letter
/// and that day's status, with a soft accent line hanging below it when
/// it's the centered day - the line the shown day's session grows out of.
class DayOval extends StatelessWidget {
  final WeekDayStatus day;
  final double scale;
  final bool isSelected;

  const DayOval(
      {super.key,
      required this.day,
      required this.scale,
      this.isSelected = false});

  static const _ovalWidth = 56.0;
  static const _ovalHeight = 88.0;
  static const _lineHeight = 30.0;

  static double width(double scale) => _ovalWidth * scale;

  /// Total row height that also fits the centered day's hanging connector
  /// line, so a parent giving this a fixed cross-axis extent (e.g. a
  /// horizontal `ListView`) never clips it.
  static double heightWithConnector(double scale) =>
      _ovalHeight * scale + AppSpacing.sm * scale + _lineHeight * scale;

  bool get _isToday {
    final now = DateTime.now();
    return day.date.year == now.year &&
        day.date.month == now.month &&
        day.date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    const weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final letter = weekdayLetters[day.date.weekday - 1];
    final isToday = _isToday;
    final isFuture = dateOnly(day.date).isAfter(dateOnly(DateTime.now()));
    final completed = day.status == 'Completed';
    final isRest = day.status == 'ActiveRest';
    final width = _ovalWidth * scale;
    final height = _ovalHeight * scale;
    final radius = width / 2;

    Color fill = AppColors.surfaceContainerHigh;
    Color letterColor = AppColors.onSurfaceVariant;
    Widget mark;

    if (isToday) {
      fill = AppColors.accent;
      letterColor = AppColors.onAccent;
      mark =
          Icon(Icons.bolt_rounded, color: AppColors.onAccent, size: 26 * scale);
    } else if (completed) {
      letterColor = AppColors.accent;
      mark =
          Icon(Icons.check_rounded, color: AppColors.accent, size: 26 * scale);
    } else if (isRest) {
      letterColor = AppColors.secondary;
      mark = Icon(Icons.nightlight_round,
          color: AppColors.secondary, size: 22 * scale);
    } else if (isFuture) {
      // A training day still to come, per the split's rotation - a light
      // mark rather than a bare number, which would otherwise read the
      // same as a past, missed day.
      mark = Icon(Icons.fitness_center_rounded,
          color: AppColors.onSurfaceVariant, size: 21 * scale);
    } else {
      // Past, not completed and not a rest day - Missed.
      mark = Text('${day.date.day}',
          style: AppTypography.labelSm.copyWith(
              color: AppColors.onSurfaceVariant, fontSize: 17 * scale));
    }

    // Tense, not selection, decides solid vs. dashed - a past day (today
    // included) is always solid, a future one is always dashed, full stop,
    // so the strip reads as a timeline at a glance regardless of what's
    // centered. Selection is layered on top as emphasis only: the centered
    // day's outline switches to accent and thickens, but keeps its own
    // tense's dash pattern rather than forcing solid. `isToday`'s own accent
    // fill is distinct enough on its own not to need an outline at all.
    final _PillBorderStyle borderStyle = isToday
        ? _PillBorderStyle.none
        : (isFuture ? _PillBorderStyle.dashed : _PillBorderStyle.solid);
    // `outlineVariant` reads as almost the same color as the pill's own fill
    // in both palettes (that's the point of a "variant" token) - fine for a
    // hairline divider, invisible as a pill outline. `outline` itself has
    // the contrast against `surfaceContainerHigh` to actually read as a
    // border for the un-selected past/future pills.
    final borderColor = isSelected ? AppColors.accent : AppColors.outline;
    final borderWidth = (isSelected ? 2.2 : 1.4) * scale;

    final oval = CustomPaint(
      foregroundPainter: borderStyle == _PillBorderStyle.none
          ? null
          : _PillBorderPainter(
              style: borderStyle,
              color: borderColor,
              strokeWidth: borderWidth,
              dashLength: 5 * scale,
              gapLength: 4 * scale),
      // Size is a plain `SizedBox`, not animated: it's driven by `scale`,
      // a dashboard-wide value this strip also sizes the item extent, side
      // padding and connector line off of *synchronously*, every frame
      // (including the frames of `FitHeight`'s own glide between scales).
      // Animating just this box's own width/height on top of that would
      // let it lag a frame behind those, so for one heartbeat the outer,
      // unanimated `Column` (oval + connector) was taller than the
      // fixed-height row it sits in - a bottom overflow, and the pill it
      // clipped read as off-center. Only the decoration (fill color, e.g.
      // a day flipping to "Completed") still animates, since that never
      // affects layout size.
      child: SizedBox(
        width: width,
        height: height,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            // Same pill shape as the fill itself (not a plain circle - this
            // oval is narrower than it is tall) so the outline traces the
            // day, not an unrelated shape dropped on top of it.
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(letter,
                  style: AppTypography.labelSm.copyWith(
                      fontSize: 18 * scale,
                      fontWeight: FontWeight.w700,
                      color: letterColor)),
              SizedBox(height: AppSpacing.xs * scale),
              mark,
            ],
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        oval,
        if (isSelected)
          Container(
            width: 3 * scale,
            height: _lineHeight * scale,
            margin: EdgeInsets.only(top: AppSpacing.sm * scale),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.accent, AppColors.accent.withOpacity(0)],
              ),
            ),
          ),
      ],
    );
  }
}

enum _PillBorderStyle { none, solid, dashed }

/// Traces a stadium/pill outline - solid or dashed - around whatever this
/// paints over. A plain `Border` inside `BoxDecoration` can't do dashed, so
/// this walks the same pill-shaped path `BoxDecoration` would draw (radius
/// pinned to the shorter side, matching [DayOval]'s own fill) and, for a
/// dashed style, chops it into short strokes instead of stroking it whole.
class _PillBorderPainter extends CustomPainter {
  const _PillBorderPainter({
    required this.style,
    required this.color,
    required this.strokeWidth,
    this.dashLength = 4,
    this.gapLength = 3.5,
  });

  final _PillBorderStyle style;
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.width < size.height ? size.width : size.height) / 2;
    // Inset by half the stroke so the outline sits just inside the fill's
    // own edge rather than straddling it and getting clipped by siblings.
    final rect = Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2,
        size.width - strokeWidth, size.height - strokeWidth);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    if (style == _PillBorderStyle.solid) {
      canvas.drawRRect(rrect, paint);
      return;
    }

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + dashLength;
        canvas.drawPath(
          metric.extractPath(distance, end.clamp(0.0, metric.length)),
          paint,
        );
        distance = end + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PillBorderPainter oldDelegate) =>
      style != oldDelegate.style ||
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      dashLength != oldDelegate.dashLength ||
      gapLength != oldDelegate.gapLength;
}

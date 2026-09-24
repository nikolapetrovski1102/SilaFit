import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../exercises/exercises_models.dart';

// The "ink" look shared by split creation and editing: borderless big type
// over a bottom rule that fills on focus, and exercises that hop from a
// search result into the day's chips.

// Motion. Short and ease-out so each step lands before the next keystroke.
const kInkMorph = Duration(milliseconds: 340);
const kInkQuick = Duration(milliseconds: 200);
const kInkFlight = Duration(milliseconds: 380);

// The big input's type starts at max and shrinks with the text so it keeps
// filling one line; only once it hits min does it wrap.
const double kHeroMaxSize = 56;
const double kHeroMinSize = 34;

TextStyle heroStyle(double size) => AppTypography.headlineLg.copyWith(
      fontSize: size,
      height: 1.1,
      letterSpacing: -0.03 * size,
    );

/// The largest type size in [kHeroMinSize, kHeroMaxSize] that fits [text]
/// on one line of [width] - so it shrinks as they type, and wraps only once
/// it's at the minimum.
double fitHeroSize(BuildContext context, String text, double width) {
  final scaler = MediaQuery.textScalerOf(context);
  // Room the editable reserves for the caret, plus rounding slack, so a size
  // that "just fits" here never wraps in the real field.
  final available = width - 12;
  bool fits(double size) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: heroStyle(size)),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout(maxWidth: available);
    final fits = !painter.didExceedMaxLines && painter.width <= available;
    painter.dispose();
    return fits;
  }

  if (fits(kHeroMaxSize)) return kHeroMaxSize;
  if (!fits(kHeroMinSize)) return kHeroMinSize;
  // Largest fitting size, to the half point.
  var lo = kHeroMinSize, hi = kHeroMaxSize;
  while (hi - lo > 0.5) {
    final mid = (lo + hi) / 2;
    if (fits(mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Every border spelled out: `.collapsed` only clears `border`, so the app
/// theme's accent `focusedBorder` (and its fill) would still show. The
/// [FocusUnderline] is the only border.
InputDecoration inkDecoration(String hint, TextStyle style) => InputDecoration(
      hintText: hint,
      hintStyle:
          style.copyWith(color: AppColors.onSurfaceVariant.withOpacity(0.5)),
      isCollapsed: true,
      contentPadding: EdgeInsets.zero,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
    );

/// A borderless field over its own [FocusUnderline]. [hero] fields use the
/// big auto-fitting type; the rest use [style].
class InkField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool hero;
  final TextStyle? style;
  final bool autofocus;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  /// Keeps focus (and the keyboard) on submit instead of dropping it.
  final bool keepFocusOnSubmit;

  /// Makes the text a [InkTextHero] with this tag (hero fields only), so it
  /// can fly in from a title on the previous screen.
  final Object? heroTag;

  const InkField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.hero = false,
    this.style,
    this.autofocus = false,
    this.textInputAction = TextInputAction.done,
    this.textCapitalization = TextCapitalization.words,
    this.onChanged,
    this.onSubmitted,
    this.keepFocusOnSubmit = false,
    this.heroTag,
  });

  @override
  State<InkField> createState() => _InkFieldState();
}

class _InkFieldState extends State<InkField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _underline = AnimationController(
    vsync: this,
    duration: kInkMorph,
    value: widget.focusNode.hasFocus ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(InkField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    _underline.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (widget.focusNode.hasFocus) {
      _underline.forward();
    } else {
      _underline.reverse();
    }
  }

  Widget _field(TextStyle style) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      // Titles wrap (once they're down at min size); other fields stay one
      // line. An explicit text keyboard keeps the action key submitting.
      minLines: 1,
      maxLines: widget.hero ? null : 1,
      keyboardType: TextInputType.text,
      style: style,
      cursorColor: AppColors.accent,
      textCapitalization: widget.textCapitalization,
      textInputAction: widget.textInputAction,
      decoration: inkDecoration(widget.hint, style),
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      onEditingComplete: widget.keepFocusOnSubmit ? () {} : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget field = widget.hero
        ? LayoutBuilder(
            builder: (context, constraints) =>
                ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              // Re-fit on every keystroke. Applied directly rather than
              // tweened - an in-between size is larger than the fit and
              // would wrap for a frame.
              builder: (context, value, _) {
                final style = heroStyle(fitHeroSize(
                    context,
                    value.text.isEmpty ? widget.hint : value.text,
                    constraints.maxWidth));
                final field = _field(style);
                final tag = widget.heroTag;
                if (tag == null) return field;
                return InkTextHero(
                    tag: tag, text: value.text, style: style, child: field);
              },
            ),
          )
        : _field(widget.style ?? AppTypography.headlineSm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        SizedBox(height: widget.hero ? AppSpacing.sm : AppSpacing.xs),
        FocusUnderline(animation: _underline),
      ],
    );
  }
}

/// Hero tags for a split day's heading, shared by the split editor's day
/// list and the day editor.
String dayTitleHeroTag(String splitDayId) => 'split-day-title-$splitDayId';
String dayEyebrowHeroTag(String splitDayId) => 'split-day-eyebrow-$splitDayId';

/// A [Hero] for a piece of text whose type changes between the two screens
/// (e.g. a list title flying into a big editable title): the flight redraws
/// [text] with its style lerped from the smaller end to the larger.
class InkTextHero extends StatelessWidget {
  final Object tag;
  final String text;
  final TextStyle style;
  final Widget child;

  const InkTextHero({
    super.key,
    required this.tag,
    required this.text,
    required this.style,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      flightShuttleBuilder: _shuttle,
      child: _HeroText(text: text, style: style, child: child),
    );
  }

  static Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    // The route animation runs 0 -> 1 on push and 1 -> 0 on pop, so reading
    // both ends as "pushed from" / "pushed to" keeps one lerp for both.
    final pushed = direction == HeroFlightDirection.push;
    final from = ((pushed ? fromHeroContext : toHeroContext).widget as Hero)
        .child as _HeroText;
    final to = ((pushed ? toHeroContext : fromHeroContext).widget as Hero).child
        as _HeroText;
    final toBox = (pushed ? toHeroContext : fromHeroContext).findRenderObject();
    final wrapWidth = toBox is RenderBox && toBox.hasSize
        ? toBox.size.width
        : double.infinity;
    final text = to.text.isNotEmpty ? to.text : from.text;
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = Curves.easeInOutCubic.transform(animation.value);
          return OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: wrapWidth,
            maxHeight: double.infinity,
            child: Text(text, style: TextStyle.lerp(from.style, to.style, t)),
          );
        },
      ),
    );
  }
}

class _HeroText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Widget child;

  const _HeroText(
      {required this.text, required this.style, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// The field's only border: a faint bottom rule that an accent line fills
/// left-to-right on focus and drains out to the right on blur.
class FocusUnderline extends StatelessWidget {
  final AnimationController animation;

  const FocusUnderline({super.key, required this.animation});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: AppColors.outlineVariant.withOpacity(0.5)),
          AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final draining = animation.status == AnimationStatus.reverse;
              return Align(
                alignment:
                    draining ? Alignment.centerRight : Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: Curves.easeInOutCubic.transform(animation.value),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

TextStyle get _rowNameStyle =>
    AppTypography.bodyMd.copyWith(color: AppColors.highEmphasis);
TextStyle get _chipStyle => AppTypography.bodySm
    .copyWith(color: AppColors.highEmphasis, fontWeight: FontWeight.w600);
Color get _rowColor => AppColors.surfaceContainer.withOpacity(0.6);
Color get _chipColor => AppColors.surfaceContainerHigh;

/// A tappable search result - the start of an exercise's flight.
class ExerciseResultRow extends StatelessWidget {
  final ExerciseSummary exercise;
  final VoidCallback onTap;

  const ExerciseResultRow(
      {super.key, required this.exercise, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _rowColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // Keeps focus (and the keyboard) on the search field.
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _rowNameStyle),
                    if (exercise.muscleGroup.isNotEmpty)
                      Text(
                        exercise.muscleGroup,
                        style: AppTypography.labelSm
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              Icon(Icons.add_rounded, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// An exercise on a day - where a flight lands. Hidden until it has.
class ExerciseChip extends StatelessWidget {
  final String label;

  /// Trailing faint text, e.g. the sets x reps target.
  final String? detail;
  final bool visible;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const ExerciseChip({
    super.key,
    required this.label,
    this.detail,
    this.visible = true,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: visible ? 1 : 0,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.fromLTRB(14, 8, onRemove == null ? 14 : 8, 8),
          decoration: BoxDecoration(
            color: _chipColor,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _chipStyle),
              ),
              if (detail != null) ...[
                const SizedBox(width: 6),
                Text(detail!,
                    style: AppTypography.labelSm
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onRemove,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(Icons.close_rounded,
                      size: 16, color: AppColors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// [key]'s widget rect in the coordinates of [context]'s overlay.
Rect? overlayRectOf(BuildContext context, GlobalKey? key) {
  final box = key?.currentContext?.findRenderObject();
  final overlay = Overlay.of(context).context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  if (overlay is! RenderBox) return null;
  return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
}

/// Flies [label] from a result row at [from] into a chip at [to], in the
/// overlay. Returns the entry so the caller can drop it on dispose.
OverlayEntry flyExercise(
  BuildContext context, {
  required String label,
  required Rect from,
  required Rect to,
  required VoidCallback onLanded,
  double? toRadius,
}) {
  late final OverlayEntry flight;
  flight = OverlayEntry(
    builder: (_) => _ExerciseFlight(
      label: label,
      from: from,
      to: to,
      toRadius: toRadius,
      onDone: () {
        if (flight.mounted) flight.remove();
        onLanded();
      },
    ),
  );
  Overlay.of(context).insert(flight);
  return flight;
}

/// The shared-element hop from a search result row into its day chip, drawn
/// in the overlay between the two rects.
class _ExerciseFlight extends StatefulWidget {
  final String label;
  final Rect from;
  final Rect to;

  /// Corner radius on landing; defaults to a pill (half the height).
  final double? toRadius;
  final VoidCallback onDone;

  const _ExerciseFlight({
    required this.label,
    required this.from,
    required this.to,
    this.toRadius,
    required this.onDone,
  });

  @override
  State<_ExerciseFlight> createState() => _ExerciseFlightState();
}

class _ExerciseFlightState extends State<_ExerciseFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: kInkFlight)
        ..forward().whenComplete(() => widget.onDone());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_controller.value);
        final rect = Rect.lerp(widget.from, widget.to, t)!;
        // A small arc so the hop reads as a lift, not a slide.
        final lift = -18 * (1 - (2 * t - 1) * (2 * t - 1));
        return Positioned.fromRect(
          rect: rect.shift(Offset(0, lift)),
          child: IgnorePointer(
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Color.lerp(_rowColor, _chipColor, t),
                  borderRadius: BorderRadius.circular(
                      lerpDouble(14, widget.toRadius ?? rect.height / 2, t)!),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18 * (1 - t)),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: TextStyle.lerp(_rowNameStyle, _chipStyle, t),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A slim top row in place of an AppBar: a back button, an optional
/// [title] filling the middle, then [actions] pushed to the right.
class InkTopBar extends StatelessWidget {
  final IconData backIcon;
  final Widget? title;
  final List<Widget> actions;

  const InkTopBar({
    super.key,
    this.backIcon = Icons.arrow_back_ios_new_rounded,
    this.title,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxs, AppSpacing.xxs, AppSpacing.xs, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(backIcon, size: 20),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(child: title ?? const SizedBox.shrink()),
          ...actions,
        ],
      ),
    );
  }
}

/// A tiny spinner for "saving in the background" in an [InkTopBar].
class InkSavingDot extends StatelessWidget {
  final bool visible;

  const InkSavingDot({super.key, required this.visible});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: kInkQuick,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: SizedBox.square(
          dimension: 14,
          child: visible
              ? CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.onSurfaceVariant)
              : null,
        ),
      ),
    );
  }
}

/// Committed text travelling from where it was typed ([fromTop], big) to its
/// resting slot ([toTop], [toStyle]) - the "lift into the header" motion.
class InkMorphText extends StatefulWidget {
  final String text;
  final double fromTop;
  final double toTop;
  final TextStyle fromStyle;
  final TextStyle toStyle;

  /// Line cap once it has settled; it wraps freely while travelling.
  final int maxLines;

  const InkMorphText({
    super.key,
    required this.text,
    required this.fromTop,
    required this.toTop,
    required this.fromStyle,
    required this.toStyle,
    this.maxLines = 2,
  });

  @override
  State<InkMorphText> createState() => _InkMorphTextState();
}

class _InkMorphTextState extends State<InkMorphText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: kInkMorph)..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(
                top: lerpDouble(widget.fromTop, widget.toTop, t)!),
            child: Text(
              widget.text,
              // Free to wrap like the input did while it travels; clamped
              // once it has settled into its slot.
              maxLines: _controller.isCompleted ? widget.maxLines : null,
              overflow: _controller.isCompleted ? TextOverflow.ellipsis : null,
              style: TextStyle.lerp(widget.fromStyle, widget.toStyle, t),
            ),
          ),
        );
      },
    );
  }
}

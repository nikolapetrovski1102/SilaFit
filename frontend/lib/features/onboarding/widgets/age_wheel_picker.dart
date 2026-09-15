import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// The vertical scroll-wheel used for age: a plain stack of numbers with the
/// centered value picked out in a solid accent pill, everything else
/// dimming and shrinking the further it sits from center - unlike the
/// horizontal drag-to-scrub [NumericWheelPicker] used for height/weight,
/// this one is a real momentum-scrolling wheel ([ListWheelScrollView]) since
/// age has no unit toggle or sub-unit precision to make horizontal scrubbing
/// worthwhile.
class AgeWheelPicker extends StatefulWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const AgeWheelPicker({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<AgeWheelPicker> createState() => _AgeWheelPickerState();
}

/// A softer, slower-settling variant of the default wheel snap: lower
/// spring stiffness and a higher damping ratio so the wheel eases into its
/// resting item instead of snapping there abruptly.
class _SoftFixedExtentPhysics extends FixedExtentScrollPhysics {
  const _SoftFixedExtentPhysics({super.parent});

  @override
  _SoftFixedExtentPhysics applyTo(ScrollPhysics? ancestor) =>
      _SoftFixedExtentPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 0.9, stiffness: 42, ratio: 1.05);
}

class _AgeWheelPickerState extends State<AgeWheelPicker> {
  static const _itemExtent = 96.0;
  static const _selectionHeight = 116.0;

  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: widget.value - widget.min);
  late int _lastReportedIndex = widget.value - widget.min;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  // Repaints every frame of the scroll (fling included) so each number's
  // size/color keeps tracking its live distance from center instead of only
  // updating once the wheel settles.
  void _onScroll() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AgeWheelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value || !_controller.hasClients) return;
    final targetIndex = widget.value - widget.min;
    if (_controller.selectedItem != targetIndex) {
      _lastReportedIndex = targetIndex;
      _controller.animateToItem(
        targetIndex,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  double _centerOffsetInItems() {
    if (!_controller.hasClients || !_controller.position.hasContentDimensions) {
      return (widget.value - widget.min).toDouble();
    }
    return _controller.offset / _itemExtent;
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.max - widget.min + 1;
    final centerOffset = _centerOffsetInItems();

    return SizedBox(
      width: double.infinity,
      height: _itemExtent * 4.15,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Container(
              height: _selectionHeight,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(34),
                border: Border.all(
                  color: AppColors.onAccent.withValues(alpha: 0.12),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
          ),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0, 0.13, 0.35, 0.87, 1],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: ListWheelScrollView.useDelegate(
              controller: _controller,
              itemExtent: _itemExtent,
              diameterRatio: 3.8,
              perspective: 0.0012,
              physics: const _SoftFixedExtentPhysics(
                parent: BouncingScrollPhysics(),
              ),
              onSelectedItemChanged: (index) {
                if (index != _lastReportedIndex) {
                  _lastReportedIndex = index;
                  HapticFeedback.selectionClick();
                  widget.onChanged(widget.min + index);
                }
              },
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: count,
                builder: (context, index) {
                  final distance = (index - centerOffset).abs();
                  final closeness = (1 - distance).clamp(0.0, 1.0);
                  final fontSize = 38 + 40 * closeness;
                  final neighborOpacity =
                      (0.16 + (1 - distance.clamp(0.0, 2.0) / 2) * 0.38)
                          .clamp(0.16, 0.54);
                  final color = closeness > 0.5
                      ? Color.lerp(AppColors.onSurfaceVariant,
                          AppColors.onAccent, closeness)!
                      : AppColors.onSurfaceVariant
                          .withValues(alpha: neighborOpacity);
                  return Center(
                    child: Text(
                      '${widget.min + index}',
                      style: AppTypography.displayStatMobile.copyWith(
                        fontSize: fontSize,
                        height: 1,
                        letterSpacing: -0.035 * fontSize,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

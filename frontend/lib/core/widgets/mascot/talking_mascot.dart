import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'ram_mascot.dart';

/// One thing Sila says: the expression to show and the words in the bubble.
class MascotLine {
  final RamArt art;
  final String text;

  const MascotLine(this.art, this.text);
}

/// Sila next to a speech bubble. The text types itself out while Sila
/// bobs as if talking, then both settle. When the [line] changes, it talks
/// again. With reduced motion turned on, the full line appears at once.
///
/// Screen readers get the whole line in one go ("Sila says: ..."), never
/// the partially typed text.
class TalkingMascot extends StatefulWidget {
  final MascotLine line;
  final double mascotSize;

  const TalkingMascot({super.key, required this.line, this.mascotSize = 64});

  @override
  State<TalkingMascot> createState() => _TalkingMascotState();
}

class _TalkingMascotState extends State<TalkingMascot>
    with SingleTickerProviderStateMixin {
  static const _perCharacter = Duration(milliseconds: 24);
  static const _startDelay = 0.12; // fraction of the run spent before typing

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _durationFor(widget.line));

  static Duration _durationFor(MascotLine line) =>
      _perCharacter * line.text.length + const Duration(milliseconds: 260);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Dependencies change for unrelated reasons too (the keyboard opening
    // changes MediaQuery), so only the first call starts talking. Later
    // calls just honour a reduced-motion switch.
    if (!_started) {
      _started = true;
      _talk();
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(TalkingMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.text != widget.line.text) {
      _controller.duration = _durationFor(widget.line);
      _talk();
    }
  }

  void _talk() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.line.text;
    return Semantics(
      container: true,
      label: '$mascotName says: $text',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final typed = ((t - _startDelay) / (1 - _startDelay))
                .clamp(0.0, 1.0);
            final visibleChars = (text.length * typed).round();
            final talking = t > 0 && t < 1;
            // A quick bob plus a slight squash while talking.
            final wave = talking ? math.sin(t * math.pi * 14) : 0.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..translateByDouble(0.0, -2.5 * wave.abs(), 0.0, 1.0)
                    ..scaleByDouble(1 + 0.03 * wave, 1 - 0.03 * wave, 1.0, 1.0),
                  child: RamMascot(widget.line.art,
                      size: widget.mascotSize, excludeFromSemantics: true),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: widget.mascotSize * 0.18),
                    child: _Bubble(text: text, visibleChars: visibleChars),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final int visibleChars;

  const _Bubble({required this.text, required this.visibleChars});

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.bodyMd.copyWith(
      color: AppColors.onSurface,
      height: 1.35,
      fontWeight: FontWeight.w500,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh.withValues(alpha: 0.92),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
        // A small bottom-left corner turns the box into a chat bubble that
        // points back at Sila.
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft: Radius.circular(4),
        ),
      ),
      // The untyped remainder is laid out but transparent, so the bubble is
      // full-size from the first frame and never reflows while typing.
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(text: text.substring(0, visibleChars)),
            TextSpan(
              text: text.substring(visibleChars),
              style: const TextStyle(color: Colors.transparent),
            ),
          ],
        ),
      ),
    );
  }
}

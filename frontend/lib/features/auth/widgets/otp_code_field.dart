import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Lets a caller (the register wizard's verify step) trigger the field's
/// reject-shake from outside - e.g. once the server comes back and says the
/// submitted code was wrong - without the field needing to know anything
/// about API calls itself.
class OtpCodeFieldController {
  _OtpCodeFieldState? _state;

  void _attach(_OtpCodeFieldState state) => _state = state;
  void _detach(_OtpCodeFieldState state) {
    if (identical(_state, state)) _state = null;
  }

  /// Shakes the boxes, then clears them and refocuses for a retry - call
  /// this when the emailed code the user typed turns out to be wrong.
  void shakeAndClear() => _state?._shakeAndClear();
}

/// 6 boxed digits for the email-verification code. A single invisible
/// [TextField] actually owns the keyboard/cursor/backspace behavior - the
/// boxes underneath are purely an animated rendering of its current value -
/// which sidesteps the focus-juggling and backspace-across-boxes bugs that
/// come with wiring up one real text field per digit.
class OtpCodeField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final OtpCodeFieldController? controller;

  const OtpCodeField({
    super.key,
    required this.onChanged,
    this.onCompleted,
    this.controller,
  });

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField>
    with SingleTickerProviderStateMixin {
  static const _length = 6;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _value = '';

  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    // Repaints the active-box outline as focus comes and goes - the boxes
    // otherwise only rebuild in response to the text changing.
    _focusNode.addListener(_handleFocusChange);
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  void _handleFocusChange() => setState(() {});

  @override
  void dispose() {
    widget.controller?._detach(this);
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    setState(() => _value = value);
    widget.onChanged(value);
    if (value.length == _length) {
      _focusNode.unfocus();
      widget.onCompleted?.call(value);
    }
  }

  void _shakeAndClear() {
    _controller.clear();
    setState(() => _value = '');
    widget.onChanged('');
    HapticFeedback.mediumImpact();
    _shakeController.forward(from: 0).then((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: AnimatedBuilder(
        animation: _shakeController,
        builder: (context, child) {
          // A decaying sine wave - a few quick side-to-side wobbles that
          // settle back to center, rather than a single rigid jolt.
          final progress = _shakeController.value;
          final dx = math.sin(progress * math.pi * 6) * 10 * (1 - progress);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_length, (index) {
                final filled = index < _value.length;
                final active = index == _value.length && _focusNode.hasFocus;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  width: 44,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: filled
                        ? AppColors.surfaceContainerHigh
                        : AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppRadius.inset),
                    border: Border.all(
                      color: active ? AppColors.accent : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  // Each digit pops/fades in as it lands rather than just
                  // appearing, and the same transition plays in reverse on
                  // backspace - keyed per box+char so AnimatedSwitcher treats
                  // a changed digit (not just filled/empty) as a fresh swap.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Text(
                      filled ? _value[index] : '',
                      key: ValueKey(filled ? _value[index] : 'empty-$index'),
                      style: AppTypography.headlineMd,
                    ),
                  ),
                );
              }),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: _length,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: _handleChanged,
                  onTapOutside: (_) => _focusNode.unfocus(),
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

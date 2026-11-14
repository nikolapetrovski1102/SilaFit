import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Reveals [child] with a graffiti scrub: a fat marker zigzags back and
/// forth across the box from top to bottom, and the child shows only where
/// the marker has been. Once the scrub covers everything, the child is shown
/// as is. It stays still the whole time: nothing moves, scales or bounces,
/// only the mask grows.
///
/// The same marker idea as `MarkerDrawnTitle` and `LogoDrawSplash`. Plays
/// once on mount; give it a new key to play again. With reduced motion
/// turned on, the child appears at once.
class ScribbleReveal extends StatefulWidget {
  const ScribbleReveal({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 620),
    this.delay = Duration.zero,
    this.passes = 5,
    this.onRevealed,
  });

  final Widget child;
  final Duration duration;

  /// Wait before the marker touches down, e.g. to let a dialog fade in.
  final Duration delay;

  /// How many times the marker crosses the box. The brush is sized from it
  /// so neighbouring passes overlap and leave no gaps.
  final int passes;

  /// Fires once the child is fully shown (straight away with reduced motion).
  final VoidCallback? onRevealed;

  @override
  State<ScribbleReveal> createState() => _ScribbleRevealState();
}

class _ScribbleRevealState extends State<ScribbleReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) widget.onRevealed?.call();
        });
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onRevealed?.call();
      });
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        if (_controller.isCompleted) return child!;
        return _ScribbleMask(
          progress: Curves.easeInOut.transform(_controller.value),
          passes: widget.passes,
          child: child,
        );
      },
    );
  }
}

class _ScribbleMask extends SingleChildRenderObjectWidget {
  const _ScribbleMask(
      {required this.progress, required this.passes, super.child});

  final double progress;
  final int passes;

  @override
  _RenderScribbleMask createRenderObject(BuildContext context) =>
      _RenderScribbleMask(progress, passes);

  @override
  void updateRenderObject(BuildContext context, _RenderScribbleMask render) {
    render
      ..progress = progress
      ..passes = passes;
  }
}

class _RenderScribbleMask extends RenderProxyBox {
  _RenderScribbleMask(this._progress, this._passes);

  double _progress;
  set progress(double v) {
    if (v == _progress) return;
    _progress = v;
    markNeedsPaint();
  }

  int _passes;
  set passes(int v) {
    if (v == _passes) return;
    _passes = v;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _progress <= 0) return;

    final box = offset & size;
    final passes = _passes.clamp(1, 40);
    final step = box.height / passes;
    // Each pass is a diagonal from one side to the other, dropping one step;
    // the brush is wider than a step so the passes overlap like a real scrub.
    final brushWidth = step * 1.7;
    final path = Path()..moveTo(box.left, box.top);
    for (var i = 1; i <= passes; i++) {
      path.lineTo(i.isOdd ? box.right : box.left, box.top + step * i);
    }

    final bounds = box.inflate(brushWidth);
    final brush = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = brushWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final canvas = context.canvas;
    canvas.saveLayer(bounds, Paint());
    context.paintChild(child, offset);
    // The brush as a dstIn mask over the child, so the brush itself never
    // shows (see LogoDrawSplash for why it's this way round).
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * _progress), brush);
    }
    canvas
      ..restore()
      ..restore();
  }
}

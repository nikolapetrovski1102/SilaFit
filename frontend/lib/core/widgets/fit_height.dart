import 'package:flutter/material.dart';

/// Scales content to fill exactly the height it's given, instead of a
/// fixed guess that either leaves dead space below it or forces a scroll.
///
/// [builder] is handed a `scale` multiplier to apply to its own font
/// sizes/paddings/icon sizes (the caller decides what actually scales -
/// this widget only solves for the right number). On every frame where
/// [availableHeight] or [measureKey] changes, the content is rendered
/// once *invisibly* at 1.0x purely to measure its natural height, then the
/// visible pass uses `availableHeight / naturalHeight` (clamped to
/// [minScale]/[maxScale]) so it lands right at the edges of the space
/// instead of over- or under-filling it.
///
/// That target scale is reached with a short glide, not a snap - e.g.
/// selecting a different day on Home whose session text wraps to a
/// different number of lines changes the natural height, and cutting
/// straight to the new scale read as a jarring jump-cut across the whole
/// dashboard. Retargeting mid-glide (another day tapped before the first
/// settles) eases on from wherever the glide currently sits rather than
/// restarting from the old target, so it never visibly hitches.
class FitHeight extends StatefulWidget {
  final double availableHeight;
  final Widget Function(double scale) builder;
  final double minScale;
  final double maxScale;

  /// Seed scale used for the very first frame, before a real measurement
  /// exists - pass a rough height-ratio guess so the initial paint is
  /// already close and the post-measurement correction isn't a visible
  /// jump.
  final double initialScale;

  /// Anything that should force a remeasure when it changes, beyond
  /// [availableHeight] itself (which is always tracked) - e.g. the payload
  /// driving the content, since a different session title/split name can
  /// change how many lines something wraps to.
  final Object? measureKey;

  const FitHeight({
    super.key,
    required this.availableHeight,
    required this.builder,
    this.minScale = 0.8,
    this.maxScale = 1.6,
    this.initialScale = 1,
    this.measureKey,
  });

  @override
  State<FitHeight> createState() => _FitHeightState();
}

class _FitHeightState extends State<FitHeight>
    with SingleTickerProviderStateMixin {
  final _measureKey = GlobalKey();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  late double _targetScale =
      widget.initialScale.clamp(widget.minScale, widget.maxScale);
  late Animation<double> _scale = AlwaysStoppedAnimation(_targetScale);
  double? _measuredAvailableHeight;
  Object? _measuredKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant FitHeight old) {
    super.didUpdateWidget(old);
    _scheduleMeasure();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleMeasure() {
    if (_measuredAvailableHeight == widget.availableHeight &&
        _measuredKey == widget.measureKey) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final box = _measureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.height <= 0) return;

    _measuredAvailableHeight = widget.availableHeight;
    _measuredKey = widget.measureKey;

    final nextScale = (widget.availableHeight / box.size.height)
        .clamp(widget.minScale, widget.maxScale);
    if ((nextScale - _targetScale).abs() <= 0.01) return;

    // Glide from wherever the scale is *right now* - not from the old
    // target - so retargeting mid-glide (a second day tapped before the
    // first settles) eases smoothly onward instead of snapping back to
    // the previous target before starting the new tween.
    final tween = Tween<double>(begin: _scale.value, end: nextScale);
    _targetScale = nextScale;
    setState(() => _scale = tween.animate(_curve));
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Invisible measuring pass, always at 1.0x so the measured height
        // is a stable baseline to solve the visible scale from - `Offstage`
        // still lays this out (so it can be measured) but paints nothing
        // and reports zero size to the Stack.
        Offstage(
          child: KeyedSubtree(key: _measureKey, child: widget.builder(1)),
        ),
        AnimatedBuilder(
          animation: _scale,
          builder: (context, _) => widget.builder(_scale.value),
        ),
      ],
    );
  }
}

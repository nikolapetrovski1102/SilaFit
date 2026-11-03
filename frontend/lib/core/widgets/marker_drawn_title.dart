import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_colors.dart';

/// A page title that draws itself in with a marker, the same way
/// `RunnerDrawSplash` draws the runner mark: a round brush travels along a
/// centre path and the text is only visible where the brush has been.
///
/// For text the path is a tight zigzag that runs through each line from left
/// to right, so the title looks scribbled in letter by letter. Each
/// [playKey] animates only once per app session (the first time the page
/// opens); later visits show the plain title straight away.
///
/// Titles are set ultra large in Permanent Marker, a street-style marker
/// face, in the theme's primary colour (lime in dark mode, burgundy in
/// light - the same as the splash's runner mark).
///
/// The title leans up a few degrees ([tilt]) and carries a thin outline in
/// the page background colour, so where it crosses a card - even one in the
/// same colour - it still reads as a separate, stuck-on label.
///
/// Layout is exactly a plain [Text] - only painting is masked, tilted and
/// outlined - so it works anywhere a [Text] does, intrinsic sizing included.
class MarkerDrawnTitle extends StatefulWidget {
  const MarkerDrawnTitle(
    this.text, {
    super.key,
    required this.playKey,
    this.scale = 1,
    this.textAlign,
  });

  final String text;

  /// Identifies the page, not the wording - e.g. `today` covers every
  /// greeting variant. For pages about one item, include the item
  /// (`recipe:$id`) so each one gets its own first draw.
  final String playKey;

  /// Multiplies the responsive size, for screens that scale their layout
  /// to fit (or want a slightly smaller title).
  final double scale;
  final TextAlign? textAlign;

  /// Line box height as a multiple of the font size.
  static const double lineHeightFactor = 1.15;

  /// The street-style lean, in radians (about 3 degrees, rising to the
  /// right). Paint-only: layout and hit testing ignore it.
  static const double tilt = -0.052;

  /// Ultra-large, but sized to the phone: about 11% of the screen width
  /// (~36pt on an SE, ~44pt on a 6.1", ~48pt on a Pro Max), clamped so it
  /// never gets silly on very narrow or very wide screens.
  static double fontSizeFor(BuildContext context, {double scale = 1}) =>
      (MediaQuery.sizeOf(context).width * 0.112).clamp(34.0, 52.0) * scale;

  /// System text size still applies, but capped - the titles are already
  /// huge, and an uncapped accessibility size would push them off screen.
  static TextScaler textScalerFor(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15);

  static TextStyle streetStyle(double fontSize) => TextStyle(
        fontFamily: 'PermanentMarker',
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        height: lineHeightFactor,
        color: AppColors.accent,
        shadows: _outline(fontSize),
      );

  /// A crisp ring in the page background colour around every letter: eight
  /// unblurred copies nudged out in each direction.
  static List<Shadow> _outline(double fontSize) {
    final w = (fontSize * 0.06).clamp(2.0, 3.5);
    final color = AppColors.background;
    return [
      for (final (dx, dy) in const [
        (1.0, 0.0),
        (-1.0, 0.0),
        (0.0, 1.0),
        (0.0, -1.0),
        (0.7, 0.7),
        (-0.7, 0.7),
        (0.7, -0.7),
        (-0.7, -0.7),
      ])
        Shadow(color: color, offset: Offset(dx * w, dy * w)),
    ];
  }

  /// Keys whose animation already played this session.
  static final Set<String> _played = {};

  @visibleForTesting
  static void resetPlayed() => _played.clear();

  @override
  State<MarkerDrawnTitle> createState() => _MarkerDrawnTitleState();
}

class _MarkerDrawnTitleState extends State<MarkerDrawnTitle>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (MarkerDrawnTitle._played.contains(widget.playKey)) return;
    // Longer titles take a little longer, like writing them would.
    final ms = (widget.text.length * 70).clamp(650, 1600);
    _controller = AnimationController(
        vsync: this, duration: Duration(milliseconds: ms + 120));
    MarkerDrawnTitle._played.add(widget.playKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = _controller;
    if (controller == null ||
        controller.isAnimating ||
        controller.isCompleted) {
      return;
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      controller.value = 1;
    } else {
      controller.forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final style = MarkerDrawnTitle.streetStyle(
        MarkerDrawnTitle.fontSizeFor(context, scale: widget.scale));
    final scaler = MarkerDrawnTitle.textScalerFor(context);
    final text = Text(widget.text,
        style: style, textAlign: widget.textAlign, textScaler: scaler);
    if (controller == null) return _tilted(text);

    final lineHeight = scaler.scale(style.fontSize!) * style.height!;

    return _tilted(AnimatedBuilder(
      animation: controller,
      child: text,
      builder: (context, child) {
        if (controller.isCompleted) return child!;
        // A short beat before the pen touches down, like the splash.
        final p = Curves.easeInOut
            .transform(const Interval(0.09, 1).transform(controller.value));
        return _MarkerMask(
          progress: p,
          lineHeight: lineHeight,
          textLength: widget.text.length,
          child: child,
        );
      },
    ));
  }

  /// Leans the title up from its start (or its middle when centred), so a
  /// start-aligned title keeps its left edge on the margin and the rest rises
  /// away from whatever sits below it.
  Widget _tilted(Widget child) {
    final centred = widget.textAlign == TextAlign.center;
    return Transform.rotate(
      angle: MarkerDrawnTitle.tilt,
      alignment: centred ? Alignment.center : AlignmentDirectional.bottomStart,
      transformHitTests: false,
      child: child,
    );
  }
}

class _MarkerMask extends SingleChildRenderObjectWidget {
  const _MarkerMask({
    required this.progress,
    required this.lineHeight,
    required this.textLength,
    super.child,
  });

  final double progress;
  final double lineHeight;
  final int textLength;

  @override
  _RenderMarkerMask createRenderObject(BuildContext context) =>
      _RenderMarkerMask(progress, lineHeight, textLength);

  @override
  void updateRenderObject(BuildContext context, _RenderMarkerMask render) {
    render
      ..progress = progress
      ..lineHeight = lineHeight
      ..textLength = textLength;
  }
}

class _RenderMarkerMask extends RenderProxyBox {
  _RenderMarkerMask(this._progress, this._lineHeight, this._textLength);

  double _progress;
  set progress(double v) {
    if (v == _progress) return;
    _progress = v;
    markNeedsPaint();
  }

  double _lineHeight;
  set lineHeight(double v) {
    if (v == _lineHeight) return;
    _lineHeight = v;
    markNeedsPaint();
  }

  int _textLength;
  set textLength(int v) {
    if (v == _textLength) return;
    _textLength = v;
    markNeedsPaint();
  }

  /// The box of each laid-out line of text, so the brush only travels where
  /// there are letters (centred titles don't waste time on empty margins).
  List<Rect> _lineRects() {
    final child = this.child;
    if (child is RenderParagraph && _textLength > 0) {
      final boxes = child.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: _textLength));
      final lines = <Rect>[];
      for (final box in boxes) {
        final r = box.toRect();
        final i = lines.indexWhere(
            (l) => (l.center.dy - r.center.dy).abs() < _lineHeight / 2);
        if (i < 0) {
          lines.add(r);
        } else {
          lines[i] = lines[i].expandToInclude(r);
        }
      }
      if (lines.isNotEmpty) {
        lines.sort((a, b) => a.top.compareTo(b.top));
        return lines;
      }
    }
    final rows = (size.height / _lineHeight).round().clamp(1, 20);
    final rowH = size.height / rows;
    return [
      for (var r = 0; r < rows; r++)
        Rect.fromLTWH(0, r * rowH, size.width, rowH)
    ];
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _progress <= 0) return;

    final lines = _lineRects();
    final rowH = lines.first.height;

    // One zigzag per line, swinging between 30% and 70% of the line box -
    // with a brush that's 78% of the line tall, that covers every glyph.
    final bounds = (offset & size).inflate(rowH);
    final metrics = <(PathMetric, Rect)>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].shift(offset);
      // Each line's brush is clipped to its own band (split halfway to the
      // neighbouring lines) so it can't reveal the next line early.
      final band = Rect.fromLTRB(
        bounds.left,
        i == 0
            ? bounds.top
            : (lines[i - 1].bottom + lines[i].top) / 2 + offset.dy,
        bounds.right,
        i == lines.length - 1
            ? bounds.bottom
            : (lines[i].bottom + lines[i + 1].top) / 2 + offset.dy,
      );
      final hi = l.top + l.height * 0.30, lo = l.top + l.height * 0.70;
      final step = l.height * 0.22;
      final path = Path()..moveTo(l.left, hi);
      var x = l.left;
      var down = true;
      while (x < l.right) {
        x = (x + step).clamp(l.left, l.right);
        path.lineTo(x, down ? lo : hi);
        down = !down;
      }
      for (final m in path.computeMetrics()) {
        metrics.add((m, band));
      }
    }

    final total = metrics.fold<double>(0, (sum, m) => sum + m.$1.length);
    var remaining = total * _progress;
    final brush = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rowH * 0.78
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final canvas = context.canvas;
    canvas.saveLayer(bounds, Paint());
    for (final (m, band) in metrics) {
      if (remaining <= 0) break;
      canvas
        ..save()
        ..clipRect(band)
        ..drawPath(m.extractPath(0, remaining.clamp(0, m.length)), brush)
        ..restore();
      remaining -= m.length;
    }
    // Text paints straight onto this canvas (no layers of its own), so it
    // lands inside the srcIn layer and only shows under the brush.
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.srcIn);
    context.paintChild(child, offset);
    canvas
      ..restore()
      ..restore();
  }
}

/// A [MarkerDrawnTitle] that sits partly on top of the block below it: the
/// feet of the letters overlap [child] near its start edge, the
/// rest stays clear. The title never takes touches, so taps, drags and
/// scrolls on [child] work exactly as if the title weren't there.
///
/// [trailing] (e.g. Home's streak badge) sits at the end of the first title
/// line and stays fully interactive; the title wraps before reaching it.
class MarkerTitleOverlap extends StatelessWidget {
  const MarkerTitleOverlap({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.titleInset = 0,
    this.overlapFactor = defaultOverlapFactor,
  });

  final MarkerDrawnTitle title;
  final Widget child;
  final Widget? trailing;

  /// Start padding for the title only, for pages whose [child] runs edge
  /// to edge (e.g. Nutrition's day strip) while the title keeps the margin.
  final double titleInset;

  /// How far [child] rides up under the title's last line, as a multiple of
  /// the font size. Defaults to [defaultOverlapFactor]; anything at or below
  /// [clearOverlapFactor] keeps the letters off [child] entirely.
  final double overlapFactor;

  /// 0.26 is the empty band under the baseline in Permanent Marker, plus a
  /// light 0.1 of actual letter overlap - just the feet of the letters, at
  /// the start of the line (the tilt lifts the rest clear).
  static const double defaultOverlapFactor = 0.36;

  /// Just short of the empty band under the baseline: the title sits right
  /// on top of [child] without covering any of it.
  static const double clearOverlapFactor = 0.24;

  @override
  Widget build(BuildContext context) {
    final fontSize = MarkerDrawnTitle.textScalerFor(context)
        .scale(MarkerDrawnTitle.fontSizeFor(context, scale: title.scale));
    return _OverlapLayout(
      overlap: fontSize * overlapFactor,
      lineHeight: fontSize * MarkerDrawnTitle.lineHeightFactor,
      hasTrailing: trailing != null,
      // Paint order = list order: content, then the title over it, then
      // the trailing widget over both.
      children: [
        child,
        IgnorePointer(
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: titleInset),
            child: title,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _OverlapLayout extends MultiChildRenderObjectWidget {
  const _OverlapLayout({
    required this.overlap,
    required this.lineHeight,
    required this.hasTrailing,
    required super.children,
  });

  final double overlap;
  final double lineHeight;
  final bool hasTrailing;

  @override
  _RenderOverlap createRenderObject(BuildContext context) =>
      _RenderOverlap(overlap, lineHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderOverlap render) {
    render
      ..overlap = overlap
      ..lineHeight = lineHeight;
  }
}

class _OverlapParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderOverlap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _OverlapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _OverlapParentData> {
  _RenderOverlap(this._overlap, this._lineHeight);

  static const double _trailingGap = 12;

  double _overlap;
  set overlap(double v) {
    if (v == _overlap) return;
    _overlap = v;
    markNeedsLayout();
  }

  double _lineHeight;
  set lineHeight(double v) {
    if (v == _lineHeight) return;
    _lineHeight = v;
    markNeedsLayout();
  }

  RenderBox get _body => firstChild!;
  RenderBox get _title => childAfter(_body)!;
  RenderBox? get _trailing => childAfter(_title);

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _OverlapParentData) {
      child.parentData = _OverlapParentData();
    }
  }

  double _trailingTop(double trailingHeight) =>
      ((_lineHeight - trailingHeight) / 2).clamp(0.0, double.infinity);

  /// Where the body starts, given the title's and trailing's heights.
  double _bodyTop(double titleHeight, double? trailingHeight) {
    var top = (titleHeight - _overlap).clamp(0.0, double.infinity);
    if (trailingHeight != null) {
      // Never slide the body under the (tappable) trailing widget.
      final trailingBottom = _trailingTop(trailingHeight) + trailingHeight;
      if (top < trailingBottom) top = trailingBottom;
    }
    return top;
  }

  double _intrinsicHeight(double width, bool max) {
    final trailing = _trailing;
    double? trailingH;
    var titleWidth = width;
    if (trailing != null) {
      final tw = trailing.getMaxIntrinsicWidth(double.infinity);
      trailingH = trailing.getMaxIntrinsicHeight(tw);
      titleWidth = (width - tw - _trailingGap).clamp(0.0, double.infinity);
    }
    final titleH = max
        ? _title.getMaxIntrinsicHeight(titleWidth)
        : _title.getMinIntrinsicHeight(titleWidth);
    final bodyH = max
        ? _body.getMaxIntrinsicHeight(width)
        : _body.getMinIntrinsicHeight(width);
    final top = _bodyTop(titleH, trailingH);
    return [titleH, top + bodyH].reduce((a, b) => a > b ? a : b);
  }

  double _intrinsicWidth(double height, bool max) {
    double w(RenderBox b) =>
        max ? b.getMaxIntrinsicWidth(height) : b.getMinIntrinsicWidth(height);
    final trailing = _trailing;
    final top = w(_title) + (trailing == null ? 0 : w(trailing) + _trailingGap);
    final body = w(_body);
    return top > body ? top : body;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicHeight(width, false);
  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicHeight(width, true);
  @override
  double computeMinIntrinsicWidth(double height) =>
      _intrinsicWidth(height, false);
  @override
  double computeMaxIntrinsicWidth(double height) =>
      _intrinsicWidth(height, true);

  @override
  void performLayout() {
    final c = constraints;
    final trailing = _trailing;

    Size? trailingSize;
    if (trailing != null) {
      trailing.layout(c.loosen(), parentUsesSize: true);
      trailingSize = trailing.size;
    }

    final maxWidth = c.maxWidth;
    final titleMax = maxWidth.isFinite
        ? (maxWidth -
                (trailingSize == null ? 0 : trailingSize.width + _trailingGap))
            .clamp(0.0, double.infinity)
        : double.infinity;
    _title.layout(BoxConstraints(maxWidth: titleMax), parentUsesSize: true);

    final bodyTop = _bodyTop(_title.size.height, trailingSize?.height);
    _body.layout(BoxConstraints(minWidth: c.minWidth, maxWidth: c.maxWidth),
        parentUsesSize: true);

    final width = maxWidth.isFinite
        ? maxWidth
        : [
            _title.size.width +
                (trailingSize == null ? 0 : trailingSize.width + _trailingGap),
            _body.size.width,
          ].reduce((a, b) => a > b ? a : b);

    (_title.parentData! as _OverlapParentData).offset = Offset.zero;
    (_body.parentData! as _OverlapParentData).offset = Offset(0, bodyTop);
    if (trailing != null) {
      (trailing.parentData! as _OverlapParentData).offset = Offset(
          width - trailingSize!.width, _trailingTop(trailingSize.height));
    }

    final height = [
      _title.size.height,
      bodyTop + _body.size.height,
      if (trailingSize != null)
        _trailingTop(trailingSize.height) + trailingSize.height,
    ].reduce((a, b) => a > b ? a : b);
    size = c.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

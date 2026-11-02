import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Branded loader: the blurred SilaFit backdrop with the runner mark drawn
/// on top of it, stroke by stroke, the same way the website loader and the
/// animated icon do (`website/assets/img/branding/loader_*.svg`).
///
/// It opens on exactly what the native splash shows (the blurred backdrop
/// with no mark, see `flutter_native_splash` in `pubspec.yaml`), so the
/// hand-off from native to Flutter is invisible. Then it draws:
/// the connected body (back arm -> shoulders -> torso -> front leg) in one
/// sweep, then the trailing left leg, then the front right arm, and pops the
/// head dot in last. [onFinished] fires once the mark is complete.
class RunnerDrawSplash extends StatefulWidget {
  const RunnerDrawSplash({super.key, this.onFinished});

  final VoidCallback? onFinished;

  @override
  State<RunnerDrawSplash> createState() => _RunnerDrawSplashState();
}

class _RunnerDrawSplashState extends State<RunnerDrawSplash>
    with SingleTickerProviderStateMixin {
  /// Draw time (1.16s) plus a short beat on the finished mark.
  static const _duration = Duration(milliseconds: 1400);

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _duration);
  Map<String, ui.Image>? _pieces;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinished?.call();
    });
    _loadPieces();
  }

  Future<void> _loadPieces() async {
    final pieces = <String, ui.Image>{};
    for (final name in _RunnerPainter.pieceNames) {
      final data =
          await rootBundle.load('assets/branding/splash/runner_$name.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      pieces[name] = (await codec.getNextFrame()).image;
    }
    if (!mounted) return;
    setState(() => _pieces = pieces);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final image in _pieces?.values ?? const <ui.Image>[]) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pieces = _pieces;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            isDark
                ? 'assets/branding/splash/splash_bg_dark.png'
                : 'assets/branding/splash/splash_bg_light.png',
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
          if (pieces != null)
            Center(
              child: SizedBox(
                width: 200,
                height: 200 * _RunnerPainter.canvas.height /
                    _RunnerPainter.canvas.width,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _RunnerPainter(
                      pieces: pieces,
                      t: _controller.value * _duration.inMilliseconds / 1000,
                      // Lime on teal in dark mode, burgundy on cream in light.
                      color: AppColors.paletteFor(
                              isDark ? Brightness.dark : Brightness.light)
                          .accent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One marker stroke: a centre-line path that a round brush of [width]
/// travels along between [start] and [end] seconds, uncovering [piece].
class _Stroke {
  const _Stroke(this.piece, this.path, this.width, this.start, this.end,
      this.curve);

  final String piece;
  final Path path;
  final double width;
  final double start;
  final double end;
  final Curve curve;
}

class _RunnerPainter extends CustomPainter {
  _RunnerPainter({required this.pieces, required this.t, required this.color});

  final Map<String, ui.Image> pieces;

  /// Elapsed seconds.
  final double t;
  final Color color;

  static const pieceNames = ['body', 'leg', 'arm', 'head'];

  /// The piece images' coordinate space: the runner's crop of the
  /// 1024x1024 icon, offset by (150, 196). All paths below are in it.
  static const canvas = Size(682, 662);
  static const _origin = Offset(150, 196);

  static Path _p(List<double> v) {
    Offset o(int i) => Offset(v[i], v[i + 1]) - _origin;
    final path = Path()..moveTo(o(0).dx, o(0).dy);
    for (var i = 2; i < v.length; i += 6) {
      final a = o(i), b = o(i + 2), c = o(i + 4);
      path.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);
    }
    return path;
  }

  static final _strokes = [
    _Stroke('body', _p([340, 435, 380, 360, 440, 308, 520, 310, 590, 312, 628, 340, 616, 395, 605, 445, 540, 470, 490, 500, 440, 530, 445, 575, 500, 590]),
        180, 0.06, 0.44, Curves.easeIn),
    _Stroke('body', _p([500, 588, 565, 594, 660, 596, 654, 632, 648, 664, 560, 700, 508, 782]),
        100, 0.44, 0.62, Curves.easeOut),
    _Stroke('leg', _p([446, 584, 420, 640, 382, 680, 322, 702, 252, 730, 202, 790, 168, 838]),
        100, 0.60, 0.82, Curves.easeInOut),
    _Stroke('arm', _p([660, 378, 668, 430, 690, 466, 726, 466, 772, 462, 800, 402, 813, 344]),
        80, 0.80, 1.00, Curves.easeInOut),
  ];

  static const _headCenter = Offset(673 - 150, 268 - 196);
  static const _headStart = 1.00, _headEnd = 1.16;

  double _progress(double start, double end, Curve curve) =>
      curve.transform(((t - start) / (end - start)).clamp(0.0, 1.0));

  @override
  void paint(Canvas c, Size size) {
    c.scale(size.width / canvas.width);
    final bounds = Offset.zero & canvas;
    final tint = Paint()
      ..blendMode = BlendMode.srcIn
      ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn)
      ..filterQuality = FilterQuality.medium;

    void reveal(String piece, void Function(Canvas) drawMask) {
      final image = pieces[piece]!;
      c.saveLayer(bounds, Paint());
      drawMask(c);
      c.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          bounds,
          tint);
      c.restore();
    }

    for (final piece in ['body', 'leg', 'arm']) {
      final strokes = _strokes.where((s) => s.piece == piece && t > s.start);
      if (strokes.isEmpty) continue;
      reveal(piece, (c) {
        for (final s in strokes) {
          final brush = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;
          final p = _progress(s.start, s.end, s.curve);
          for (final metric in s.path.computeMetrics()) {
            c.drawPath(metric.extractPath(0, metric.length * p), brush);
          }
        }
      });
    }

    if (t > _headStart) {
      // Pops out from its centre with a slight overshoot.
      final r = 64 *
          Curves.easeOutBack
              .transform(((t - _headStart) / (_headEnd - _headStart + 0.06))
                  .clamp(0.0, 1.0));
      reveal('head', (c) => c.drawCircle(_headCenter, r, Paint()));
    }
  }

  @override
  bool shouldRepaint(_RunnerPainter old) => old.t != t || old.color != color;
}

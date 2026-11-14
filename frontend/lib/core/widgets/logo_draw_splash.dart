import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Branded loader: the blurred SilaFit backdrop with the brushed "SF" mark
/// painted on top of it, stroke by stroke. A port of the designer's
/// `silafit_logo_animation(_light).svg`: the same layer images (cut out into
/// `assets/branding/splash/`), brush paths and timings.
///
/// It opens on exactly what the native splash shows (the blurred backdrop
/// with no mark, see `flutter_native_splash` in `pubspec.yaml`), so the
/// hand-off from native to Flutter is invisible. Then a round brush sweeps
/// each stroke in: the S (three strokes), the F's top arm, then its bar.
/// Each stroke's drop shadow fades in behind it, and in dark mode a soft
/// glow blooms around the finished mark. [onFinished] fires once it is done.
class LogoDrawSplash extends StatefulWidget {
  const LogoDrawSplash({super.key, this.onFinished});

  final VoidCallback? onFinished;

  @override
  State<LogoDrawSplash> createState() => _LogoDrawSplashState();
}

class _LogoDrawSplashState extends State<LogoDrawSplash>
    with SingleTickerProviderStateMixin {
  /// The SVG's own timeline: it ends at 1.92s (the dark glow), plus a beat.
  static const _timeline = 2.0;

  /// Plays that timeline faster than the SVG (2.0s -> ~1.38s, about as long
  /// as the old runner splash) so cold start doesn't feel held up. The
  /// strokes finish at ~1.0s.
  static const _speed = 1.45;
  static const _duration = Duration(milliseconds: _timeline * 1000 ~/ _speed);

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _duration);

  /// Layer images per mode, keyed by file name.
  final _images = <Brightness, Map<String, ui.Image>>{};
  final _loading = <Brightness>{};

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinished?.call();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load(Theme.of(context).brightness);
  }

  Future<void> _load(Brightness brightness) async {
    if (_images.containsKey(brightness) || !_loading.add(brightness)) return;
    final mode = brightness == Brightness.dark ? 'dark' : 'light';
    final spec = _LogoPainter.specFor(brightness);
    final images = <String, ui.Image>{};
    for (final name in [
      for (final f in spec.fades) f.image,
      for (final s in _LogoPainter.strokes) s.image,
    ]) {
      final data = await rootBundle
          .load('assets/branding/splash/logo_${mode}_$name.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      images[name] = (await codec.getNextFrame()).image;
    }
    if (!mounted) {
      for (final image in images.values) {
        image.dispose();
      }
      return;
    }
    setState(() => _images[brightness] = images);
    if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final set in _images.values) {
      for (final image in set.values) {
        image.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final images = _images[brightness];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            brightness == Brightness.dark
                ? 'assets/branding/splash/splash_bg_dark.png'
                : 'assets/branding/splash/splash_bg_light.png',
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
          if (images != null)
            Center(
              // The full 1024 icon frame; the mark itself is ~180pt wide.
              child: SizedBox.square(
                dimension: 300,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _LogoPainter(
                      spec: _LogoPainter.specFor(brightness),
                      images: images,
                      t: _controller.value * _timeline,
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

/// A full-frame layer (shadow or glow) that fades in from [start] over [dur]
/// seconds.
class _Fade {
  const _Fade(this.image, this.start, this.dur);

  final String image;
  final double start;
  final double dur;
}

/// One brush stroke: a round brush of [width] travels along the polyline
/// [points] from [start] over [dur] seconds, uncovering [image] (placed at
/// [rect] in the 1024 frame) wherever it has been.
class _Stroke {
  const _Stroke(this.image, this.rect, this.width, this.start, this.dur,
      this.curve, this.points);

  final String image;
  final Rect rect;
  final double width;
  final double start;
  final double dur;
  final Curve curve;

  /// SVG polyline points: "x,y x,y ...".
  final String points;

  Path get path {
    final path = Path();
    var first = true;
    for (final pair in points.split(' ')) {
      final [x, y] = pair.split(',').map(double.parse).toList();
      first ? path.moveTo(x, y) : path.lineTo(x, y);
      first = false;
    }
    return path;
  }
}

class _ModeSpec {
  const _ModeSpec(this.fades);

  /// Drawn in order, under the strokes.
  final List<_Fade> fades;
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({required this.spec, required this.images, required this.t});

  final _ModeSpec spec;
  final Map<String, ui.Image> images;

  /// Elapsed seconds.
  final double t;

  static const _frame = 1024.0;
  static const _fadeCurve = Cubic(0.3, 0, 0.3, 1);

  static const _dark = _ModeSpec([
    _Fade('glow', 1.42, 0.5),
    _Fade('shadow_s', 0.74, 0.32),
    _Fade('shadow_arm', 1.12, 0.32),
    _Fade('shadow_bar', 1.38, 0.32),
  ]);
  static const _light = _ModeSpec([
    _Fade('shadow_s', 0.74, 0.32),
    _Fade('shadow_arm', 1.12, 0.32),
    _Fade('shadow_bar', 1.38, 0.32),
  ]);

  static _ModeSpec specFor(Brightness b) =>
      b == Brightness.dark ? _dark : _light;

  /// Shared by both modes (the two SVGs use identical masks).
  static const strokes = [
    _Stroke(
        's1',
        Rect.fromLTWH(194, 159, 285, 405),
        173,
        0.120,
        0.191,
        Cubic(0.42, 0, 0.7, 1),
        '480.3,130.8 434.5,201.5 379.5,286.5 325.0,372.8 271.0,460.2 203.7,569.4'),
    _Stroke(
        's2',
        Rect.fromLTWH(193, 310, 426, 266),
        202,
        0.346,
        0.182,
        Cubic(0.3, 0, 0.7, 1),
        '135.5,563.3 260.8,506.0 348.2,466.0 436.5,425.0 525.5,383.0 651.0,323.8'),
    _Stroke(
        's3',
        Rect.fromLTWH(193, 182, 615, 675),
        173,
        0.563,
        0.257,
        Cubic(0.3, 0, 0.4, 1),
        '593.1,287.7 556.8,358.3 554.4,362.9 550.9,369.9 546.1,379.1 540.2,390.7 '
            '533.1,404.6 524.8,420.8 515.2,439.2 505.9,457.6 496.8,475.9 487.8,494.0 '
            '479.0,512.0 470.3,529.9 461.9,547.6 453.6,565.2 445.4,582.8 437.4,600.3 '
            '429.6,618.0 421.8,635.7 414.2,653.5 406.7,671.4 399.3,689.4 392.1,707.4 '
            '384.9,725.6 378.9,742.6 373.9,758.5 370.0,773.4 367.2,787.1 365.5,799.8 '
            '364.8,811.3 365.2,821.8 366.8,831.2 368.1,839.4 369.2,846.4 370.1,852.3 '
            '370.9,857.0 371.4,860.5 371.8,862.8 377.3,897.2'),
    _Stroke(
        'arm',
        Rect.fromLTWH(544, 285, 263, 123),
        151,
        0.980,
        0.220,
        Cubic(0.42, 0, 0.35, 1),
        '517.9,370.2 578.2,361.5 640.8,352.5 705.8,342.5 773.2,331.5 836.0,321.3'),
    _Stroke(
        'bar',
        Rect.fromLTWH(447, 526, 215, 107),
        140,
        1.260,
        0.200,
        Cubic(0.42, 0, 0.35, 1),
        '423.0,595.7 475.5,588.5 526.5,581.5 579.5,574.0 634.5,566.0 689.0,558.1'),
  ];

  static final _paths = {for (final s in strokes) s.image: s.path};

  double _progress(double start, double dur, Curve curve) =>
      curve.transform(((t - start) / dur).clamp(0.0, 1.0));

  static Rect _src(ui.Image i) =>
      Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble());

  @override
  void paint(Canvas c, Size size) {
    c.scale(size.width / _frame);
    const frame = Rect.fromLTWH(0, 0, _frame, _frame);

    for (final f in spec.fades) {
      final opacity = _progress(f.start, f.dur, _fadeCurve);
      if (opacity <= 0) continue;
      final image = images[f.image]!;
      c.drawImageRect(
          image,
          _src(image),
          frame,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(0, 0, 0, opacity));
    }

    for (final s in strokes) {
      final p = _progress(s.start, s.dur, s.curve);
      if (p <= 0) continue;
      final image = images[s.image]!;
      // The piece first, then the brush composited over it as a dstIn mask
      // layer, so the brush itself never shows - masking the other way round
      // (brush, then piece with srcIn) leaves a faint brush-coloured outline
      // along the piece's edges wherever they fall between pixels.
      c.saveLayer(s.rect, Paint());
      c.drawImageRect(image, _src(image), s.rect,
          Paint()..filterQuality = FilterQuality.medium);
      c.saveLayer(s.rect, Paint()..blendMode = BlendMode.dstIn);
      final brush = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final metric in _paths[s.image]!.computeMetrics()) {
        c.drawPath(metric.extractPath(0, metric.length * p), brush);
      }
      c.restore();
      c.restore();
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.t != t || old.spec != spec || old.images != images;
}

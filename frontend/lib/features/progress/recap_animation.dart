import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../core/theme/app_colors.dart';

/// Theme the vector paints before parsing, including gradient color stops.
/// Source files remain intact; each composition is cached once per palette.
Future<LottieComposition> loadRecapComposition(
    String asset, Brightness brightness) {
  return _compositions.putIfAbsent((asset, brightness), () async {
    final json = jsonDecode(
        await rootBundle.loadString('assets/lottie_animations/$asset.json'));
    final palette = AppColors.paletteFor(brightness);
    List<double> recolor(List<dynamic> values) {
      final original = Color.fromRGBO(
          ((values[0] as num) * 255).round(),
          ((values[1] as num) * 255).round(),
          ((values[2] as num) * 255).round(),
          1);
      final hsv = HSVColor.fromColor(original);
      final Color color;
      if (hsv.saturation < .12) {
        color = hsv.value > .75 ? palette.onAccent : palette.onSurface;
      } else if (hsv.hue >= 30 && hsv.hue < 85) {
        color = palette.secondary;
      } else {
        color = Color.lerp(
            palette.accent, palette.onSurface, hsv.value < .4 ? .25 : 0)!;
      }
      return [
        color.r,
        color.g,
        color.b,
        if (values.length > 3) (values[3] as num).toDouble()
      ];
    }

    void paint(dynamic property, {int? stops}) {
      if (property is! Map) return;
      void values(List<dynamic> list) {
        if (stops == null) {
          final mapped = recolor(list);
          for (var i = 0; i < mapped.length; i++) {
            list[i] = mapped[i];
          }
        } else {
          for (var i = 0; i < stops; i++) {
            final offset = i * 4 + 1;
            final mapped = recolor(list.sublist(offset, offset + 3));
            list.setRange(offset, offset + 3, mapped);
          }
        }
      }

      final keys = property['k'];
      if (keys is List && keys.isNotEmpty) {
        if (keys.first is num) {
          values(keys);
        } else {
          for (final frame in keys) {
            if (frame is Map) {
              if (frame['s'] is List) values(frame['s']);
              if (frame['e'] is List) values(frame['e']);
            }
          }
        }
      }
    }

    void visit(dynamic node) {
      if (node is Map) {
        if (node['ty'] == 'fl' || node['ty'] == 'st') paint(node['c']);
        if (node['ty'] == 'gf' || node['ty'] == 'gs') {
          final gradient = node['g'] as Map;
          paint(gradient['k'], stops: gradient['p'] as int);
        }
        for (final value in node.values) {
          visit(value);
        }
      } else if (node is List) {
        for (final value in node) {
          visit(value);
        }
      }
    }

    visit(json);
    return LottieComposition.fromBytes(utf8.encode(jsonEncode(json)));
  });
}

final _compositions = <(String, Brightness), Future<LottieComposition>>{};

class RecapReplayNotification extends Notification {}

/// One tap replays every layer together and emits one tactile response.
class RecapAnimationStage extends StatefulWidget {
  const RecapAnimationStage({super.key, required this.child});
  final Widget child;
  @override
  State<RecapAnimationStage> createState() => _RecapAnimationStageState();
}

class _RecapAnimationStageState extends State<RecapAnimationStage> {
  int _replay = 0;
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_entered && TickerMode.valuesOf(context).enabled) {
      _entered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            TickerMode.valuesOf(context).enabled &&
            !MediaQuery.disableAnimationsOf(context)) {
          HapticFeedback.lightImpact();
        }
      });
    }
  }

  void _restart() {
    if (!TickerMode.valuesOf(context).enabled) return;
    HapticFeedback.lightImpact();
    setState(() => _replay++);
    RecapReplayNotification().dispatch(context);
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Replay animation',
        onTap: _restart,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _restart,
          child: _RecapReplay(generation: _replay, child: widget.child),
        ),
      );
}

class _RecapReplay extends InheritedWidget {
  const _RecapReplay({required this.generation, required super.child});
  final int generation;
  static int of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RecapReplay>()?.generation ??
      0;
  @override
  bool updateShouldNotify(_RecapReplay oldWidget) =>
      generation != oldWidget.generation;
}

/// Plays only while its recap page is visible, then holds the final frame.
class RecapAnimation extends StatefulWidget {
  const RecapAnimation(
      {super.key, required this.asset, this.fit = BoxFit.contain});
  final String asset;
  final BoxFit fit;

  @override
  State<RecapAnimation> createState() => _RecapAnimationState();
}

class _RecapAnimationState extends State<RecapAnimation>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final _controller = AnimationController(vsync: this);
  Future<LottieComposition>? _composition;
  Brightness? _brightness;
  int _replay = 0;
  bool _active = false;
  bool _reducedMotion = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = TickerMode.valuesOf(context).enabled;
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    final brightness = Theme.of(context).brightness;
    if (_brightness != brightness) {
      _brightness = brightness;
      _composition = loadRecapComposition(widget.asset, brightness);
    }
    final replay = _RecapReplay.of(context);
    if (_replay != replay) {
      _replay = replay;
      _controller.value = 0;
    }
    _syncPlayback();
  }

  void _syncPlayback() {
    if (_reducedMotion) {
      _controller.value = 1;
    } else if (!_active) {
      _controller.stop();
    } else if (_controller.duration != null && !_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ExcludeSemantics(
      child: FutureBuilder<LottieComposition>(
        future: _composition,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.expand();
          final composition = snapshot.data!;
          if (_controller.duration != composition.duration) {
            _controller.duration = composition.duration;
            _syncPlayback();
          }
          return Lottie(
              composition: composition,
              controller: _controller,
              repeat: false,
              fit: widget.fit);
        },
      ),
    );
  }
}

/// A custom compass entrance: the dial rises and its needle overshoots north.
class RecapCompass extends StatefulWidget {
  const RecapCompass({super.key});
  @override
  State<RecapCompass> createState() => _RecapCompassState();
}

class _RecapCompassState extends State<RecapCompass>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  int _replay = 0;
  late final _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  @override
  bool get wantKeepAlive => true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final replay = _RecapReplay.of(context);
    if (_replay != replay) {
      _replay = replay;
      _controller.value = 0;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!TickerMode.valuesOf(context).enabled) {
      _controller.stop();
    } else if (!_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_controller.value);
          final needle = Curves.easeOutBack.transform(_controller.value);
          return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 24 * (1 - t)),
                child: Transform.scale(
                    scale: .65 + .35 * t,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox(
                          width: 176,
                          height: 176,
                          child: CustomPaint(
                              painter: _CompassDial(
                                  AppColors.accent.withValues(alpha: .45)))),
                      Transform.rotate(
                          angle: (1 - needle) * -math.pi * .85,
                          child: Icon(Icons.explore_outlined,
                              size: 132, color: AppColors.accent)),
                    ])),
              ));
        });
  }
}

class _CompassDial extends CustomPainter {
  const _CompassDial(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final scale = size.shortestSide / 120;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12;
      final direction = Offset(math.sin(angle), math.cos(angle));
      canvas.drawLine(center + direction * (i % 6 == 0 ? 49 : 54) * scale,
          center + direction * 59 * scale, paint);
    }
  }

  @override
  bool shouldRepaint(_CompassDial oldDelegate) => oldDelegate.color != color;
}

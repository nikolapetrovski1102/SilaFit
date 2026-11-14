import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

/// Blurs [child] like `ImageFiltered(ImageFilter.blur(...))`, but runs the
/// blur once and then shows a cached picture of the result.
///
/// Impeller (Flutter's renderer on Android and iOS) has no raster cache,
/// so a live `ImageFiltered` blur is recomputed on the GPU on every frame
/// in which anything nearby moves: a tab swipe, a fade, a scroll of the
/// list it sits in, a spinner drawn over it. Over a whole screen of
/// content, that alone drops frames on low-end Android phones. The content
/// behind these blurs is locked and non-interactive, so a still picture of
/// it looks the same.
///
/// The picture is retaken whenever the content may have changed: when the
/// parent rebuilds this widget, when [refresh] notifies, when the locale
/// changes, or when the size changes. Each time, the live blur runs for
/// [settle] first, so loading skeletons and entrance animations finish
/// before the picture is taken instead of being frozen halfway through.
class FrozenBlur extends StatefulWidget {
  final Widget child;
  final double sigma;

  /// When false the child paints untouched: no blur and no picture. The
  /// widget tree stays the same either way, so toggling this never
  /// remounts [child] or loses its state.
  final bool enabled;

  /// Fires when [child]'s content changes without this widget being
  /// rebuilt, such as a controller the child listens to directly.
  final Listenable? refresh;

  final Duration settle;

  const FrozenBlur({
    super.key,
    required this.child,
    this.sigma = 9,
    this.enabled = true,
    this.refresh,
    this.settle = const Duration(milliseconds: 1200),
  });

  @override
  State<FrozenBlur> createState() => _FrozenBlurState();
}

class _FrozenBlurState extends State<FrozenBlur> {
  final _snapshot = SnapshotController();
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(_resettle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resettle();
  }

  @override
  void didUpdateWidget(covariant FrozenBlur oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refresh != widget.refresh) {
      oldWidget.refresh?.removeListener(_resettle);
      widget.refresh?.addListener(_resettle);
    }
    _resettle();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    widget.refresh?.removeListener(_resettle);
    _snapshot.dispose();
    super.dispose();
  }

  /// Drops any cached picture, shows the live blur, and takes a new
  /// picture once the content has had [FrozenBlur.settle] to settle.
  void _resettle() {
    _settleTimer?.cancel();
    _snapshot.allowSnapshotting = false;
    if (!widget.enabled) return;
    _settleTimer = Timer(widget.settle, () {
      if (mounted && widget.enabled) _snapshot.allowSnapshotting = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Registers a dependency, so a language switch retakes the picture.
    Localizations.maybeLocaleOf(context);
    final media = MediaQuery.of(context);
    return MediaQuery(
      // The picture is taken at this pixel ratio. Blurred content has no
      // fine detail, so capping it costs nothing visible and keeps a
      // full-screen picture at about a quarter of the memory on a 3x phone.
      data: media.copyWith(
          devicePixelRatio: math.min(media.devicePixelRatio, 1.5)),
      child: SnapshotWidget(
        controller: _snapshot,
        // Falls back to painting live if the child ever holds a platform
        // view, which can't be captured.
        mode: SnapshotMode.permissive,
        autoresize: true,
        child: MediaQuery(
          // The child itself still sees the real pixel ratio.
          data: media,
          child: ImageFiltered(
            enabled: widget.enabled,
            imageFilter:
                ImageFilter.blur(sigmaX: widget.sigma, sigmaY: widget.sigma),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

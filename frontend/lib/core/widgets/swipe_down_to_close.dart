import 'package:flutter/material.dart';

/// Dismisses an expanded card from its chrome or by pulling past the top of
/// its content. Uses maybePop so unsaved-work guards still get a say.
class SwipeDownToClose extends StatefulWidget {
  final Widget child;

  const SwipeDownToClose({super.key, required this.child});

  @override
  State<SwipeDownToClose> createState() => _SwipeDownToCloseState();
}

class _SwipeDownToCloseState extends State<SwipeDownToClose> {
  double _distance = 0;
  bool _closing = false;

  void _update(double delta) {
    _distance = (_distance + delta).clamp(0.0, double.infinity);
  }

  Future<void> _end() async {
    final shouldClose = _distance >= 80;
    _distance = 0;
    final route = ModalRoute.of(context);
    if (!shouldClose ||
        _closing ||
        route?.isCurrent != true ||
        route?.animation?.status != AnimationStatus.completed) {
      return;
    }
    _closing = true;
    await Navigator.of(context).maybePop();
    if (mounted) _closing = false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axisDirection != AxisDirection.down) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _distance = 0;
    } else if (notification is ScrollUpdateNotification) {
      final drag = notification.dragDetails;
      if (drag != null) {
        if (notification.metrics.pixels <=
            notification.metrics.minScrollExtent) {
          _update(drag.delta.dy);
        } else {
          _distance = 0;
        }
      }
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        notification.overscroll < 0) {
      _update(-notification.overscroll);
    } else if (notification is ScrollEndNotification) {
      _end();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (_) => _distance = 0,
          onVerticalDragUpdate: (details) => _update(details.delta.dy),
          onVerticalDragEnd: (_) => _end(),
          onVerticalDragCancel: () => _distance = 0,
          child: widget.child,
        ),
      );
}

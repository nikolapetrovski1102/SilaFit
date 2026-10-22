import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../session/session_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// One option behind a [SwipeActionTile] - shown both as a revealed button
/// when the tile is slid open and as a row in the hold menu.
class SwipeAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  /// Null keeps the action available; otherwise it's shown greyed out and
  /// this explains why in the hold menu.
  final String? disabledReason;

  const SwipeAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
    this.disabledReason,
  });

  bool get enabled => disabledReason == null;
}

/// Wraps a list card so its [actions] can be reached two ways: sliding the
/// card left reveals them as buttons, and holding it lifts the card out of
/// the list - it flies from its slot onto a blurred backdrop - with the
/// actions as a menu beneath it. Taps on the card still go through to
/// [child] while closed.
class SwipeActionTile extends StatefulWidget {
  final Widget child;
  final List<SwipeAction> actions;

  /// The item's name, read out as the hold menu's label.
  final String? sheetTitle;
  final double borderRadius;

  /// Plays a small slide-open-and-back on first build so the user learns the
  /// card has actions behind it. Pass it for the first card of a list only;
  /// [SessionStore] caps how often it actually plays.
  final bool showHint;

  const SwipeActionTile({
    super.key,
    required this.child,
    required this.actions,
    this.sheetTitle,
    this.borderRadius = 14,
    this.showHint = false,
  });

  @override
  State<SwipeActionTile> createState() => _SwipeActionTileState();
}

class _SwipeActionTileState extends State<SwipeActionTile>
    with TickerProviderStateMixin {
  static const _actionWidth = 76.0;

  /// Space between the slid card and its buttons, so both keep their
  /// rounded corners instead of the buttons butting up square.
  static const _actionGap = 6.0;
  static const _peekFraction = 0.42;

  late final AnimationController _reveal = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220));

  /// Sinks the card slightly while a hold is building up, so the lift reads
  /// as the card being picked up rather than jumping.
  late final AnimationController _press = AnimationController(
      vsync: this,
      duration: kLongPressTimeout,
      reverseDuration: const Duration(milliseconds: 160));

  final _cardKey = GlobalKey();

  /// True while the card is shown in the hold menu instead of its slot.
  bool _lifted = false;
  bool _peeking = false;

  double get _actionsWidth => _actionWidth * widget.actions.length;
  double get _maxSlide => _actionsWidth + _actionGap;
  bool get _isOpen => _reveal.value > 0;

  @override
  void initState() {
    super.initState();
    if (widget.showHint) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybePeek());
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    _press.dispose();
    super.dispose();
  }

  /// Null in tests and previews that don't provide one - the hint then just
  /// never plays.
  SessionStore? _hints() {
    try {
      return context.read<SessionStore>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _maybePeek() async {
    final hints = mounted ? _hints() : null;
    if (hints == null || !hints.shouldShowSwipeHint || widget.actions.isEmpty) {
      return;
    }
    hints.recordSwipeHintShown();
    // Let the list's own entrance settle first.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted || _isOpen || _lifted) return;
    _peeking = true;
    await _reveal.animateTo(_peekFraction,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    // A drag or hold during the peek takes over the reveal.
    if (!mounted || !_peeking) return;
    _peeking = false;
    await _reveal.animateTo(0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic);
  }

  void _learned() {
    _peeking = false;
    _hints()?.markSwipeActionsLearned();
  }

  void _close() => _reveal.animateTo(0, curve: Curves.easeOutCubic);

  void _onDragStart(DragStartDetails _) => _peeking = false;

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = -(details.primaryDelta ?? 0) / _maxSlide;
    final wasOpen = _reveal.value >= 1;
    _reveal.value = (_reveal.value + delta).clamp(0.0, 1.0);
    if (!wasOpen && _reveal.value >= 1) HapticFeedback.selectionClick();
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final open = velocity.abs() > 300 ? velocity < 0 : _reveal.value > 0.4;
    _reveal.animateTo(open ? 1 : 0, curve: Curves.easeOutCubic);
    if (open) _learned();
  }

  void _run(SwipeAction action) {
    _close();
    if (action.enabled) action.onTap();
  }

  Future<void> _lift() async {
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    HapticFeedback.mediumImpact();
    _learned();
    // Snap shut so the card lifts from its resting slot, not mid-slide.
    _reveal.value = 0;

    final navigator = Navigator.of(context, rootNavigator: true);
    final overlayBox = navigator.context.findRenderObject() as RenderBox?;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final route = _LiftedCardRoute(
      sourceRect: origin & box.size,
      startScale: _pressScale,
      borderRadius: widget.borderRadius,
      label: widget.sheetTitle,
      actions: widget.actions,
      card: widget.child,
    );
    setState(() => _lifted = true);
    _press.value = 0;

    final future = navigator.push(route);
    // The card only returns to its slot once the flight back has landed.
    route.animation!.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _lifted = false);
      }
    });
    final chosen = await future;
    if (chosen != null && chosen.enabled && mounted) chosen.onTap();
  }

  double get _pressScale => lerpDouble(1, 0.97, _press.value)!;

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressDown: (_) => _press.forward(),
      onLongPressCancel: () => _press.reverse(),
      onLongPressStart: (_) => _lift(),
      onLongPressEnd: (_) => _press.reverse(),
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      // The key sits outside the press scale so the lift measures the card's
      // resting rect.
      child: KeyedSubtree(
        key: _cardKey,
        child: Opacity(
          opacity: _lifted ? 0 : 1,
          child: AnimatedBuilder(
            animation: _press,
            builder: (context, child) =>
                Transform.scale(scale: _pressScale, child: child),
            child: _buildSlider(),
          ),
        ),
      ),
    );
  }

  Widget _buildSlider() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        children: [
          // Only the strip the card has slid off of shows the buttons, so
          // see-through cards never have them peeking through.
          AnimatedBuilder(
            animation: _reveal,
            builder: (context, _) => Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: math.max(0, _maxSlide * _reveal.value - _actionGap),
              // Rounded like the card, so the group reads as its own pill
              // at every width the card has slid.
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: _actionsWidth,
                  maxWidth: _actionsWidth,
                  child: Row(
                    children: [
                      for (final action in widget.actions)
                        _ActionButton(
                          action: action,
                          width: _actionWidth,
                          onTap: () => _run(action),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _reveal,
            builder: (context, child) => Transform.translate(
              offset: Offset(-_maxSlide * _reveal.value, 0),
              child: child,
            ),
            // While slid open, a tap on the card just closes it rather than
            // opening whatever the card leads to.
            child: AnimatedBuilder(
              animation: _reveal,
              // Same widget shape open or closed, so the card keeps its state.
              builder: (context, child) => GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _isOpen ? _close : null,
                child: AbsorbPointer(absorbing: _isOpen, child: child),
              ),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

/// The hold menu: a copy of the card flies from [sourceRect] to a lifted
/// spot (nudged up when the menu wouldn't fit below it), over a blurred,
/// dimmed backdrop, and the actions unfold beneath it. Popping flies it back.
class _LiftedCardRoute extends PopupRoute<SwipeAction> {
  final Rect sourceRect;
  final double startScale;
  final double borderRadius;
  final String? label;
  final List<SwipeAction> actions;
  final Widget card;

  _LiftedCardRoute({
    required this.sourceRect,
    required this.startScale,
    required this.borderRadius,
    required this.label,
    required this.actions,
    required this.card,
  });

  @override
  Color? get barrierColor => null;

  // The page draws and handles its own backdrop.
  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return _LiftedCard(route: this, animation: animation);
  }
}

/// Dragging anywhere moves the lifted card with the finger; letting go far
/// or fast enough closes the menu (the card flies home from where it was
/// dropped), otherwise it springs back.
class _LiftedCard extends StatefulWidget {
  final _LiftedCardRoute route;
  final Animation<double> animation;

  const _LiftedCard({required this.route, required this.animation});

  @override
  State<_LiftedCard> createState() => _LiftedCardState();
}

class _LiftedCardState extends State<_LiftedCard>
    with SingleTickerProviderStateMixin {
  static const _gap = 10.0;
  static const _dismissDistance = 70.0;
  static const _dismissVelocity = 700.0;
  static const _liftScale = 1.03;
  static const _menuMaxWidth = 250.0;
  static const _rowHeight = 50.0;
  static const _rowWithReasonHeight = 64.0;

  _LiftedCardRoute get route => widget.route;
  Animation<double> get animation => widget.animation;

  /// Where the drag has taken the card, relative to its lifted spot.
  Offset _drag = Offset.zero;
  bool _dismissing = false;

  late final AnimationController _springBack = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260))
    ..addListener(
        () => setState(() => _drag = _springFrom * (1 - _springCurve)));
  Offset _springFrom = Offset.zero;
  double get _springCurve => Curves.easeOutBack.transform(_springBack.value);

  @override
  void dispose() {
    _springBack.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails _) {
    if (_dismissing) return;
    _springBack.stop();
    HapticFeedback.selectionClick();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dismissing) return;
    setState(() => _drag += details.delta);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_dismissing) return;
    final fast = details.velocity.pixelsPerSecond.distance > _dismissVelocity;
    if (fast || _drag.distance > _dismissDistance) {
      _dismissing = true;
      Navigator.of(context).pop();
      return;
    }
    _springFrom = _drag;
    _springBack.forward(from: 0);
  }

  /// 0 at rest, 1 once the drag is far enough to close.
  double get _dragProgress =>
      (_drag.distance / _dismissDistance).clamp(0.0, 1.0);

  double get _menuHeight =>
      route.actions.fold(0.0,
          (sum, a) => sum + (a.enabled ? _rowHeight : _rowWithReasonHeight)) +
      math.max(0, route.actions.length - 1);

  Rect _targetRect(MediaQueryData media) {
    final source = route.sourceRect;
    final top = media.padding.top + 12;
    final bottom = media.size.height - media.padding.bottom - 12;
    final needed = source.height * (1 + _liftScale) / 2 + _gap + _menuHeight;
    var y = source.top;
    if (y + needed > bottom) y = bottom - needed;
    if (y < top) y = top;
    return Rect.fromLTWH(source.left, y, source.width, source.height);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final source = route.sourceRect;
    final target = _targetRect(media);
    final move = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic);
    final pop = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic);
    final menuIn = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
        reverseCurve: const Interval(0, 0.6, curve: Curves.easeInCubic));
    final menuWidth = math.min(_menuMaxWidth, source.width);

    return Material(
      type: MaterialType.transparency,
      // A swipe from anywhere - card, menu or backdrop - drags the card.
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        // Any heroes inside the copied card stay with the original.
        child: HeroMode(
          enabled: false,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = move.value;
              // The drag rides on the lifted spot, so the flight home starts
              // wherever the card was let go.
              final rect = Rect.lerp(source, target.shift(_drag), t)!;
              final drag = _dragProgress;
              final scale =
                  lerpDouble(route.startScale, _liftScale, pop.value)! *
                      (1 - 0.06 * drag);
              final dim = t * (1 - 0.4 * drag);
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                            sigmaX: 14 * dim, sigmaY: 14 * dim),
                        child: ColoredBox(
                            color: Colors.black.withOpacity(0.35 * dim)),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: rect,
                    child: Transform.scale(
                      scale: scale,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(route.borderRadius),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.28 * t),
                              blurRadius: 28 * t,
                              offset: Offset(0, 10 * t),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(route.borderRadius),
                          child: IgnorePointer(child: route.card),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: rect.left,
                    // Below the card as drawn, scale included.
                    top: rect.bottom + rect.height * (scale - 1) / 2 + _gap,
                    width: menuWidth,
                    child: FadeTransition(
                      opacity: menuIn.drive(Tween(begin: 0.0, end: 1 - drag)),
                      child: ScaleTransition(
                        scale: Tween(begin: 0.8, end: 1.0).animate(menuIn),
                        alignment: Alignment.topLeft,
                        child: _Menu(
                          label: route.label,
                          actions: route.actions,
                          rowHeight: _rowHeight,
                          rowWithReasonHeight: _rowWithReasonHeight,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  final String? label;
  final List<SwipeAction> actions;
  final double rowHeight;
  final double rowWithReasonHeight;

  const _Menu({
    required this.label,
    required this.actions,
    required this.rowHeight,
    required this.rowWithReasonHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      container: true,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 1, thickness: 1, color: AppColors.outlineVariant),
              _menuRow(context, actions[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _menuRow(BuildContext context, SwipeAction action) {
    final color = action.isDestructive ? AppColors.error : AppColors.onSurface;
    return Opacity(
      opacity: action.enabled ? 1 : 0.45,
      child: InkWell(
        onTap: action.enabled
            ? () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(action);
              }
            : null,
        child: SizedBox(
          height: action.enabled ? rowHeight : rowWithReasonHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(action.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMd.copyWith(color: color)),
                      if (!action.enabled)
                        Text(action.disabledReason!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelSm
                                .copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(action.icon, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final SwipeAction action;
  final double width;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.action, required this.width, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final background = action.isDestructive
        ? AppColors.errorContainer
        : AppColors.secondaryContainer;
    final foreground = action.isDestructive
        ? AppColors.onErrorContainer
        : AppColors.onSecondaryContainer;
    return Opacity(
      opacity: action.enabled ? 1 : 0.4,
      child: Material(
        color: background,
        child: InkWell(
          onTap: action.enabled ? onTap : null,
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, color: foreground, size: 22),
                const SizedBox(height: 4),
                Text(action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSm.copyWith(color: foreground)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

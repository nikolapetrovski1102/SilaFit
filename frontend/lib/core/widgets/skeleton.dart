import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shimmering placeholder shown while a screen's content loads, in place of
/// a spinner - the page keeps its shape, so the real content lands where the
/// eye already is instead of popping in around a centered indicator.
///
/// [Skeleton] owns the one animation every [Bone] under it shares. Each bone
/// paints the same diagonal highlight band at its own offset inside the
/// host, so the sweep reads as one light passing over the whole layout
/// rather than every bar pulsing on its own. Bones repaint off the animation
/// directly (no rebuilds), and the host is a repaint boundary so the sweep
/// never dirties anything around it.
class Skeleton extends StatefulWidget {
  final Widget child;

  const Skeleton({super.key, required this.child});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce-motion users get static bones - still the page's shape, just
    // without the sweep.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: _SkeletonScope(
        state: this,
        child: Semantics(
          label: 'Loading',
          container: true,
          child: ExcludeSemantics(child: widget.child),
        ),
      ),
    );
  }
}

class _SkeletonScope extends InheritedWidget {
  final _SkeletonState state;

  const _SkeletonScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) => false;
}

/// One placeholder bar/block. Outside a [Skeleton] it simply paints flat.
class Bone extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const Bone({super.key, this.width, this.height = 12, this.radius = 6});

  /// A line of text roughly [fontSize] tall.
  const Bone.text({super.key, this.width, double fontSize = 14})
      : height = fontSize * 0.8,
        radius = 4;

  const Bone.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = size / 2;

  @override
  Widget build(BuildContext context) {
    final scope =
        context.getInheritedWidgetOfExactType<_SkeletonScope>()?.state;
    final base = AppColors.surfaceContainerHigh;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _BonePainter(
          animation: scope?._controller,
          host: scope?.context,
          bone: context,
          radius: radius,
          base: base,
          highlight: Color.lerp(base, AppColors.surfaceBright, 0.55)!,
        ),
      ),
    );
  }
}

class _BonePainter extends CustomPainter {
  final Animation<double>? animation;
  final BuildContext? host;
  final BuildContext bone;
  final double radius;
  final Color base;
  final Color highlight;

  _BonePainter({
    required this.animation,
    required this.host,
    required this.bone,
    required this.radius,
    required this.base,
    required this.highlight,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    final paint = Paint()..color = base;

    final hostBox = host?.findRenderObject() as RenderBox?;
    final boneBox = bone.findRenderObject() as RenderBox?;
    if (animation != null &&
        hostBox != null &&
        boneBox != null &&
        hostBox.hasSize &&
        boneBox.attached) {
      // The band travels across the host's full width (plus its own width
      // either side, so it enters and leaves fully off-screen); every bone
      // shifts the gradient by its own offset so they all share one band.
      final hostWidth = hostBox.size.width;
      final origin = boneBox.localToGlobal(Offset.zero, ancestor: hostBox);
      final band = hostWidth * 0.6;
      final x = -band + (hostWidth + band * 2) * animation!.value - origin.dx;
      paint.shader = LinearGradient(
        colors: [base, highlight, base],
        stops: const [0, 0.5, 1],
        transform: const GradientRotation(0.3),
      ).createShader(Rect.fromLTWH(x, -origin.dy, band, hostBox.size.height));
    }
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_BonePainter old) =>
      old.base != base || old.highlight != highlight || old.radius != radius;
}

/// Card-shaped container for bones - the same rounded, flat surface as
/// `SectionCard`, one step quieter so the bones read on top of it.
class SkeletonCard extends StatelessWidget {
  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  const SkeletonCard({
    super.key,
    required this.child,
    this.height,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: child,
    );
  }
}

/// Generic list-of-cards placeholder: each row an icon tile, a title line and
/// a shorter subtitle line. The default for any `ResourceBuilder` that
/// doesn't pass its own skeleton.
class SkeletonList extends StatelessWidget {
  final int count;
  final bool leading;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.count = 4,
    this.leading = true,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.md),
  });

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              SkeletonListRow(leading: leading, seed: i),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single list-row card. [seed] varies the line widths so a stack of rows
/// doesn't look stamped out.
class SkeletonListRow extends StatelessWidget {
  final bool leading;
  final int seed;

  const SkeletonListRow({super.key, this.leading = true, this.seed = 0});

  @override
  Widget build(BuildContext context) {
    const titleFactors = [0.62, 0.48, 0.7, 0.55];
    const subFactors = [0.38, 0.52, 0.3, 0.44];
    return SkeletonCard(
      child: Row(
        children: [
          if (leading) ...[
            const Bone(width: 44, height: 44, radius: AppRadius.inset),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone.text(
                      width: c.maxWidth * titleFactors[seed % 4],
                      fontSize: 18),
                  const SizedBox(height: AppSpacing.xs),
                  Bone.text(width: c.maxWidth * subFactors[seed % 4]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paragraph placeholder - [lines] text bars, the last one short.
class SkeletonParagraph extends StatelessWidget {
  final int lines;
  final double fontSize;

  const SkeletonParagraph({super.key, this.lines = 3, this.fontSize = 14});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines; i++) ...[
            if (i > 0) SizedBox(height: fontSize * 0.55),
            Bone.text(
                width: i == lines - 1 && lines > 1
                    ? c.maxWidth * 0.6
                    : c.maxWidth,
                fontSize: fontSize),
          ],
        ],
      ),
    );
  }
}

/// Detail-page placeholder: a large hero card, a title and paragraph, then a
/// few row cards - the shape every split / diet plan / guide detail shares.
class SkeletonDetail extends StatelessWidget {
  final int rows;

  const SkeletonDetail({super.key, this.rows = 3});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SkeletonCard(
              height: 168,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Bone(width: 72, height: 18, radius: AppRadius.full),
                  SizedBox(height: AppSpacing.sm),
                  Bone.text(width: 200, fontSize: 26),
                  SizedBox(height: AppSpacing.xs),
                  Bone.text(width: 140),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SkeletonParagraph(lines: 3),
            const SizedBox(height: AppSpacing.xl),
            const Bone.text(width: 96, fontSize: 11),
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < rows; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              SkeletonListRow(seed: i),
            ],
          ],
        ),
      ),
    );
  }
}

/// Settings-style placeholder: eyebrow-headed groups of short rows.
class SkeletonSections extends StatelessWidget {
  final int sections;
  final int rowsPerSection;

  const SkeletonSections(
      {super.key, this.sections = 3, this.rowsPerSection = 3});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var s = 0; s < sections; s++) ...[
              if (s > 0) const SizedBox(height: AppSpacing.xl),
              const Bone.text(width: 110, fontSize: 11),
              const SizedBox(height: AppSpacing.sm),
              SkeletonCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.cardPadding,
                    vertical: AppSpacing.xs),
                child: Column(
                  children: [
                    for (var r = 0; r < rowsPerSection; r++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm),
                        child: Row(
                          children: [
                            const Bone(
                                width: 28, height: 28, radius: AppRadius.inset),
                            const SizedBox(width: AppSpacing.md),
                            Bone.text(
                                width: 90.0 + ((s * 3 + r) % 4) * 28,
                                fontSize: 16),
                            const Spacer(),
                            const Bone(width: 40, height: 22, radius: 11),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single standalone card placeholder of a fixed [height], e.g. one
/// section of a screen that loads independently of the rest.
class SkeletonBlock extends StatelessWidget {
  final double height;
  final int lines;

  const SkeletonBlock({super.key, this.height = 140, this.lines = 2});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: SkeletonCard(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Bone.text(width: 110, fontSize: 11),
            const SizedBox(height: AppSpacing.md),
            Flexible(child: SkeletonParagraph(lines: lines)),
          ],
        ),
      ),
    );
  }
}

/// Calendar/heatmap placeholder - [rows] x [columns] rounded day cells.
class SkeletonGrid extends StatelessWidget {
  final int columns;
  final int rows;

  const SkeletonGrid({super.key, this.columns = 7, this.rows = 5});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: LayoutBuilder(builder: (context, c) {
        const gap = AppSpacing.xs;
        final cell = (c.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < rows; r++) ...[
              if (r > 0) const SizedBox(height: gap),
              Row(
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    Bone(width: cell, height: cell, radius: AppRadius.inset),
                  ],
                ],
              ),
            ],
          ],
        );
      }),
    );
  }
}

/// Card-less row placeholders for content that loads *inside* an existing
/// card (a section of a screen whose header is already on screen).
class SkeletonRows extends StatelessWidget {
  final int count;

  const SkeletonRows({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: LayoutBuilder(
        builder: (context, c) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Bone(width: 36, height: 36, radius: AppRadius.inset),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Bone.text(
                            width: c.maxWidth * (0.45 + (i % 3) * 0.08),
                            fontSize: 16),
                        const SizedBox(height: AppSpacing.xxs + 2),
                        Bone.text(width: c.maxWidth * 0.28, fontSize: 12),
                      ],
                    ),
                  ),
                  const Bone(width: 48, height: 16),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chart placeholder: a row of pill toggles over a plot-sized block.
class SkeletonChart extends StatelessWidget {
  final double height;

  const SkeletonChart({super.key, this.height = 180});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Bone(width: 72, height: 28, radius: AppRadius.full),
              SizedBox(width: AppSpacing.xs),
              Bone(width: 72, height: 28, radius: AppRadius.full),
              SizedBox(width: AppSpacing.xs),
              Bone(width: 72, height: 28, radius: AppRadius.full),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Bone(height: height, radius: AppRadius.inset),
        ],
      ),
    );
  }
}

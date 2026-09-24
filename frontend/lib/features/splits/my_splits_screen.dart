import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../auth/widgets/auth_blob_background.dart';
import '../today/today_controller.dart';
import 'split_builder_screen.dart';
import 'split_creation_wizard_screen.dart';
import 'splits_controller.dart';
import 'splits_models.dart';
import 'splits_repository.dart';
import 'splits_screen.dart';
import 'widgets/split_hero_image.dart';

/// The user's own splits - built via the in-app builder, always fully
/// editable. This is the Home "MY SPLIT" card's destination: a premium
/// listing of what the user has created, a big "Create Split" entry point
/// into the step-by-step wizard, and a link out to the full ranked/browsable
/// library ([SplitsScreen]) for anyone still looking for a starting point.
class MySplitsScreen extends StatefulWidget {
  const MySplitsScreen({super.key});

  @override
  State<MySplitsScreen> createState() => _MySplitsScreenState();
}

class _MySplitsScreenState extends State<MySplitsScreen> {
  late final MySplitsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<MySplitsController>();
    Future.microtask(_controller.load);
  }

  Future<void> _openWizard() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SplitCreationWizardScreen(
        existingSplitCount: _controller.state.data?.length ?? 0,
      ),
    ));
    if (!mounted) return;
    _controller.load(force: true);
    context.read<TodayController>().load(force: true);
  }

  void _openBuilder(String splitId) async {
    final repository = context.read<SplitsRepository>();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SplitBuilderScreen(
        controller: SplitBuilderController(repository, splitId: splitId),
      ),
    ));
    if (!mounted) return;
    _controller.load(force: true);
  }

  Future<void> _activateSplit(WorkoutSplit split) async {
    final repository = context.read<SplitsRepository>();
    try {
      await repository.activate(split.splitId);
      if (!mounted) return;
      // Home's dashboard is loaded once and cached, so without this the newly
      // activated split's session (and its exercises) would not appear until
      // a manual pull-to-refresh - see the matching comment in
      // split_detail_screen.dart.
      context.read<TodayController>().load(force: true);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${split.name} is now your active split.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.userMessage)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(ApiException.genericMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeSplit =
        context.watch<TodayController>().state.data?.activeSplit;

    return Scaffold(
      backgroundColor: AppColors.background,
      // Lets the blob backdrop bleed all the way behind the (transparent)
      // AppBar instead of stopping at the body's normal top edge - matching
      // SplitBuilderScreen and login/register.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: AuthBlobBackground(layout: 3)),
          AnimatedBuilder(
            animation: _controller,
            // The top inset already covers the status bar and the AppBar
            // (extendBodyBehindAppBar folds its height in). The bottom is left
            // open so the list scrolls behind the home indicator instead of
            // stopping at a blank band.
            builder: (context, _) => SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.marginMobile,
                    AppSpacing.xs,
                    AppSpacing.marginMobile,
                    AppSpacing.xxl + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionEyebrow('Your Training', color: AppColors.accent),
                    const SizedBox(height: 4),
                    Text('My Splits', style: AppTypography.headlineLg),
                    const SizedBox(height: AppSpacing.lg),
                    _CreateSplitCta(onTap: _openWizard),
                    if (activeSplit == null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text('No active split yet',
                          style: AppTypography.headlineSm),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Create one to get your training rolling.',
                          style: AppTypography.bodyMd
                              .copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                    ResourceBuilder<List<WorkoutSplit>>(
                      state: _controller.state,
                      onRetry: _controller.load,
                      builder: (context, splits) {
                        if (splits.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: AppSpacing.lg),
                            const SectionEyebrow('Your splits'),
                            const SizedBox(height: AppSpacing.sm),
                            for (final split in splits) ...[
                              _MySplitCard(
                                split: split,
                                isActive: activeSplit?.splitId == split.splitId,
                                onTap: () => _openBuilder(split.splitId),
                                onActivate: () => _activateSplit(split),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SuggestedSplitsRow(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const SplitsScreen())),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Always-visible entry point into [SplitCreationWizardScreen] - the one
/// loud element above the fold, same role the "activate" affordance used to
/// play, but now pointed at building rather than picking.
class _CreateSplitCta extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateSplitCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.accent, AppColors.accent.withOpacity(0.78)],
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.onAccent.withOpacity(0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_rounded, color: AppColors.onAccent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Create Split',
                      style: AppTypography.headlineSm
                          .copyWith(color: AppColors.onAccent)),
                  const SizedBox(height: 2),
                  Text('One simple step at a time',
                      style: AppTypography.bodySm.copyWith(
                          color: AppColors.onAccent.withOpacity(0.85))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: AppColors.onAccent),
          ],
        ),
      ),
    );
  }
}

/// One of the user's own splits, styled with the same premium hero-image
/// card language as `_SplitCard` in splits_screen.dart, plus the activate
/// affordance the plain row used to carry.
class _MySplitCard extends StatefulWidget {
  final WorkoutSplit split;
  final bool isActive;
  final VoidCallback onTap;
  final Future<void> Function() onActivate;

  const _MySplitCard({
    required this.split,
    required this.isActive,
    required this.onTap,
    required this.onActivate,
  });

  @override
  State<_MySplitCard> createState() => _MySplitCardState();
}

class _MySplitCardState extends State<_MySplitCard> {
  bool _activating = false;

  Future<void> _handleActivate() async {
    if (_activating) return;
    setState(() => _activating = true);
    await widget.onActivate();
    if (!mounted) return;
    setState(() => _activating = false);
  }

  @override
  Widget build(BuildContext context) {
    final split = widget.split;
    return GestureDetector(
      onTap: widget.onTap,
      child: SectionCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.inset)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: SplitHeroImage(split.heroImageUrl),
                  ),
                ),
                if (widget.isActive)
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(AppRadius.full)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded,
                              size: 12, color: AppColors.onAccent),
                          const SizedBox(width: 6),
                          Text('ACTIVE',
                              style: AppTypography.labelCaps
                                  .copyWith(color: AppColors.onAccent)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(split.name,
                      style: AppTypography.headlineSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            _MetaPill(
                                icon: Icons.calendar_view_week_rounded,
                                label: '${split.durationDays} days'),
                            _MetaPill(
                                icon: Icons.trending_up_rounded,
                                label: split.level),
                          ],
                        ),
                      ),
                      if (widget.isActive)
                        Text('Active',
                            style: AppTypography.labelSm
                                .copyWith(color: AppColors.accent))
                      else
                        _activating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                tooltip: 'Set as active split',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(Icons.play_circle_outline_rounded,
                                    color: AppColors.accent),
                                onPressed: _handleActivate,
                              ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 4),
          Text(label,
              style: AppTypography.labelSm
                  .copyWith(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Bottom link out to the full ranked/browsable library - unchanged,
/// server-ranked "best for you" experience in [SplitsScreen].
class _SuggestedSplitsRow extends StatelessWidget {
  final VoidCallback onTap;

  const _SuggestedSplitsRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SectionCard(
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: AppColors.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('Suggested splits',
                  style: AppTypography.bodyMd
                      .copyWith(fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

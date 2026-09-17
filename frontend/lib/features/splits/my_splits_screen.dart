import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/mascot/mascot_empty_state.dart';
import '../../core/widgets/section_card.dart';
import '../auth/widgets/auth_blob_background.dart';
import 'split_builder_screen.dart';
import 'splits_controller.dart';
import 'splits_models.dart';
import 'splits_repository.dart';

/// The user's own splits - built via the in-app builder, always fully
/// editable. Reached from [SplitsScreen]'s "My splits" action.
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

  void _openBuilder({String? splitId}) async {
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
    return Scaffold(
      backgroundColor: AppColors.background,
      // See the matching comment in SplitBuilderScreen - lets the blob
      // backdrop reach behind the transparent AppBar instead of stopping at
      // the body's normal top edge.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('My Splits', style: AppTypography.headlineSm),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openBuilder(),
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New split'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // See the matching comment in SplitBuilderScreen - layout 3 keeps
          // every blob inside the visible viewport instead of relying on
          // fixed footer content to cover the space below it.
          const Positioned.fill(child: AuthBlobBackground(layout: 3)),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => SafeArea(
              child: RefreshIndicator(
                onRefresh: () => _controller.load(force: true),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // Extra top inset makes up for `extendBodyBehindAppBar`,
                  // same reasoning as SplitBuilderScreen's padding.
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.marginMobile,
                      AppSpacing.sm + kToolbarHeight,
                      AppSpacing.marginMobile,
                      AppSpacing.xxl),
                  child: ResourceBuilder<List<WorkoutSplit>>(
                    state: _controller.state,
                    onRetry: _controller.load,
                    minHeight: 320,
                    builder: (context, splits) {
                      if (splits.isEmpty) {
                        return const MascotEmptyState(
                          title: 'No splits yet',
                          message:
                              'Build your own training split - tap "New split" to start.',
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final split in splits) ...[
                            _MySplitRow(
                              split: split,
                              onTap: () => _openBuilder(splitId: split.splitId),
                              onActivate: () => _activateSplit(split),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                        ],
                      );
                    },
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

class _MySplitRow extends StatefulWidget {
  final WorkoutSplit split;
  final VoidCallback onTap;
  final Future<void> Function() onActivate;

  const _MySplitRow(
      {required this.split, required this.onTap, required this.onActivate});

  @override
  State<_MySplitRow> createState() => _MySplitRowState();
}

class _MySplitRowState extends State<_MySplitRow> {
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
    return GestureDetector(
      onTap: widget.onTap,
      child: SectionCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.split.name,
                      style: AppTypography.headlineSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${widget.split.durationDays} days • ${widget.split.level}',
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _activating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'Set as active split',
                    icon: Icon(Icons.play_circle_outline_rounded,
                        color: AppColors.accent),
                    onPressed: _handleActivate,
                  ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

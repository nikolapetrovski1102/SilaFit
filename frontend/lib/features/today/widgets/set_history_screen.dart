import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/state/resource_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/section_eyebrow.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/upgrade_lock_card.dart';
import '../../plans/plans_screen.dart';
import '../today_models.dart';
import '../today_repository.dart';

/// Full breakdown of every set logged for a completed past day, grouped by
/// exercise in the order they were worked. Reached from Home's "View set
/// history" link on `_buildCompleted()` (see `overview_card.dart`) - only
/// ever pushed for a day that's already been completed, so an empty result
/// here means the day predates per-set logging rather than nothing to show.
/// Also opened from the streak sheet's day dots; Free accounts only see the
/// last 14 days, so an older day (or a 403) shows the upgrade card instead.
class SetHistoryScreen extends StatefulWidget {
  final DateTime date;
  final String? sessionTitle;

  /// Skip the fetch and go straight to the upgrade card - the caller already
  /// knows the day is outside the account's history window.
  final bool locked;

  const SetHistoryScreen(
      {super.key, required this.date, this.sessionTitle, this.locked = false});

  @override
  State<SetHistoryScreen> createState() => _SetHistoryScreenState();
}

class _SetHistoryScreenState extends State<SetHistoryScreen> {
  ResourceState<List<SetLogHistoryEntry>> _state =
      const ResourceState.loading();
  late bool _locked = widget.locked;

  @override
  void initState() {
    super.initState();
    if (!_locked) _load();
  }

  Future<void> _load() async {
    setState(() => _state = const ResourceState.loading());
    try {
      final entries =
          await context.read<TodayRepository>().getWorkoutHistory(widget.date);
      if (!mounted) return;
      setState(() => _state = ResourceState.data(entries));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => e.isForbidden
          ? _locked = true
          : _state = ResourceState.error(e.userMessage));
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = const ResourceState.error(
          "Couldn't load set history. Please try again."));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Set History', style: AppTypography.headlineSm),
      ),
      body: SafeArea(
        child: _locked
            ? _buildLocked()
            : ResourceBuilder(
                state: _state,
                onRetry: _load,
                minHeight: 320,
                skeleton: const SkeletonList(
                    count: 5, padding: EdgeInsets.all(AppSpacing.gutterMobile)),
                builder: (context, entries) => _SetHistoryList(
                  date: widget.date,
                  sessionTitle: widget.sessionTitle,
                  entries: entries,
                ),
              ),
      ),
    );
  }

  Widget _buildLocked() {
    return ListView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutterMobile, vertical: AppSpacing.lg),
      children: [
        SectionEyebrow(DateFormat('EEEE, MMM d').format(widget.date)),
        const SizedBox(height: AppSpacing.sm),
        UpgradeLockCard(
          title: 'See your full month of training',
          message: 'Free shows the sets from your last 14 days. Pro and '
              'Advanced open every workout from the past month.',
          actionLabel: 'See plans',
          onUnlock: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const PlansScreen())),
        ),
      ],
    );
  }
}

class _SetHistoryList extends StatelessWidget {
  final DateTime date;
  final String? sessionTitle;
  final List<SetLogHistoryEntry> entries;

  const _SetHistoryList(
      {required this.date, required this.sessionTitle, required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutterMobile, vertical: 64),
        child: Center(
          child: Text(
            'No set-by-set history was recorded for this session.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ),
      );
    }

    final grouped = <String, List<SetLogHistoryEntry>>{};
    final order = <String>[];
    for (final entry in entries) {
      if (!grouped.containsKey(entry.exerciseId)) {
        grouped[entry.exerciseId] = [];
        order.add(entry.exerciseId);
      }
      grouped[entry.exerciseId]!.add(entry);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutterMobile, vertical: AppSpacing.lg),
      children: [
        Text(sessionTitle ?? 'Training Session',
            style: AppTypography.headlineLg),
        const SizedBox(height: AppSpacing.xxs),
        Text(DateFormat('EEEE, MMM d').format(date),
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.lg),
        for (final exerciseId in order) ...[
          _ExerciseSetsCard(sets: grouped[exerciseId]!),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _ExerciseSetsCard extends StatelessWidget {
  final List<SetLogHistoryEntry> sets;

  const _ExerciseSetsCard({required this.sets});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionEyebrow(sets.first.exerciseName),
          const SizedBox(height: AppSpacing.sm),
          for (final set in sets)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text('Set ${set.setNumber}',
                        style: AppTypography.bodyMd
                            .copyWith(color: AppColors.onSurfaceVariant)),
                  ),
                  Expanded(
                    child: Text(
                        '${_formatWeight(set.weightKg)} kg × ${set.reps}',
                        style: AppTypography.numericUnit
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatWeight(double weightKg) => weightKg == weightKg.roundToDouble()
      ? weightKg.toStringAsFixed(0)
      : weightKg.toStringAsFixed(1);
}

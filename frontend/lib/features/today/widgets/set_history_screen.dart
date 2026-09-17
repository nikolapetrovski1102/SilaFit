import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/state/resource_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/section_eyebrow.dart';
import '../today_models.dart';
import '../today_repository.dart';

/// Full breakdown of every set logged for a completed past day, grouped by
/// exercise in the order they were worked. Reached from Home's "View set
/// history" link on `_buildCompleted()` (see `overview_card.dart`) - only
/// ever pushed for a day that's already been completed, so an empty result
/// here means the day predates per-set logging rather than nothing to show.
class SetHistoryScreen extends StatefulWidget {
  final DateTime date;
  final String? sessionTitle;

  const SetHistoryScreen({super.key, required this.date, this.sessionTitle});

  @override
  State<SetHistoryScreen> createState() => _SetHistoryScreenState();
}

class _SetHistoryScreenState extends State<SetHistoryScreen> {
  ResourceState<List<SetLogHistoryEntry>> _state =
      const ResourceState.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const ResourceState.loading());
    try {
      final entries =
          await context.read<TodayRepository>().getWorkoutHistory(widget.date);
      if (!mounted) return;
      setState(() => _state = ResourceState.data(entries));
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
        child: ResourceBuilder(
          state: _state,
          onRetry: _load,
          minHeight: 320,
          builder: (context, entries) => _SetHistoryList(
            date: widget.date,
            sessionTitle: widget.sessionTitle,
            entries: entries,
          ),
        ),
      ),
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

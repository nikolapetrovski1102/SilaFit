import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'progress_models.dart';
import 'progress_repository.dart';
import 'widgets/personal_record_tile.dart';

/// Every exercise the account has a logged Personal Record for - not just the
/// top-3 preview the Progress tab's card shows. Fetches independently of
/// [ProgressController] (same pattern as the AI review entries) rather than
/// widening the shared `prsState`, so the card's own request can stay cheap.
class AllPersonalRecordsScreen extends StatefulWidget {
  const AllPersonalRecordsScreen({super.key});

  @override
  State<AllPersonalRecordsScreen> createState() =>
      _AllPersonalRecordsScreenState();
}

class _AllPersonalRecordsScreenState extends State<AllPersonalRecordsScreen> {
  ResourceState<List<PersonalRecord>> _state = const ResourceState.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  // No exerciser realistically logs a PR for more than a couple hundred
  // exercises - a high, fixed `top` is simpler than adding an "unlimited"
  // sentinel to the API just for this screen.
  Future<void> _load() async {
    setState(() => _state = const ResourceState.loading());
    try {
      final records = await context
          .read<ProgressRepository>()
          .getPersonalRecords(top: 200);
      if (!mounted) return;
      setState(() => _state = ResourceState.data(records));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _state = ResourceState.error(e.userMessage));
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = const ResourceState.error(ApiException.genericMessage));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Personal Records', style: AppTypography.headlineSm),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.gutterMobile),
          child: ResourceBuilder<List<PersonalRecord>>(
            state: _state,
            onRetry: _load,
            builder: (context, records) {
              if (records.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 64),
                  child: Center(
                    child: Text('Log a set during a workout to start tracking PRs.',
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.onSurfaceVariant)),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final record in records) PersonalRecordTile(record: record),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'exercise_video_sheet.dart';
import 'exercise_web_search.dart';

/// Icon-only button on a search/suggestion row that previews an exercise's
/// form without picking it - its demo video when there is one, otherwise an
/// in-app web search, so there's always a one-tap way to look it up. Tapping
/// the row itself still selects the exercise, so this needs its own
/// hit-testable region rather than living inside the row's own tap target.
class ExerciseFormButton extends StatelessWidget {
  final String exerciseName;
  final String? demoUrl;

  const ExerciseFormButton({
    super.key,
    required this.exerciseName,
    this.demoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final url = demoUrl;
    final videoUrl = url != null && isVideoUrl(url) ? url : null;
    return Tooltip(
      message: videoUrl == null ? 'Search for form' : 'Watch form',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => videoUrl == null
            ? openExerciseWebSearch(context, exerciseName: exerciseName)
            : showExerciseVideoSheet(context,
                url: videoUrl, exerciseName: exerciseName),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            videoUrl == null
                ? Icons.travel_explore_rounded
                : Icons.play_circle_outline_rounded,
            size: 20,
            color: videoUrl == null
                ? AppColors.onSurfaceVariant
                : AppColors.accent,
          ),
        ),
      ),
    );
  }
}

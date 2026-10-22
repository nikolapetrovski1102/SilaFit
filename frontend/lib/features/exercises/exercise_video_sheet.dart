import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Whether [url] points at a real video file. Only a video gets the in-app
/// sheet below - anything else in `Exercise.DemoVideoUrl` (the catalog used to
/// carry step-position JPEGs there) is ignored, and the form button falls back
/// to a web search instead.
bool isVideoUrl(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  return path.endsWith('.mp4') ||
      path.endsWith('.mov') ||
      path.endsWith('.webm') ||
      path.endsWith('.m3u8');
}

/// Opens a bottom sheet playing an exercise's form video - looping and muted
/// to start. Only call it with a [url] that passes [isVideoUrl]. Shared by the active-workout tracker (demo chip on the
/// current exercise) and the exercise picker sheet (preview while searching).
Future<void> showExerciseVideoSheet(
  BuildContext context, {
  required String url,
  required String exerciseName,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (_) => _ExerciseVideoSheet(url: url, exerciseName: exerciseName),
  );
}

class _ExerciseVideoSheet extends StatefulWidget {
  final String url;
  final String exerciseName;

  const _ExerciseVideoSheet({required this.url, required this.exerciseName});

  @override
  State<_ExerciseVideoSheet> createState() => _ExerciseVideoSheetState();
}

class _ExerciseVideoSheetState extends State<_ExerciseVideoSheet> {
  VideoPlayerController? _controller;
  bool _muted = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      _failed = true;
      return;
    }
    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      controller
        ..setLooping(true)
        ..setVolume(0)
        ..play();
      setState(() {});
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _muted = !_muted);
    controller.setVolume(_muted ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
            AppSpacing.marginMobile, AppSpacing.marginMobile, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.exerciseName,
                      style: AppTypography.headlineSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.close_rounded,
                      size: 22, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.inset),
              child: AspectRatio(
                aspectRatio: ready ? controller.value.aspectRatio : 4 / 3,
                child: Container(
                  color: AppColors.surfaceContainerLowest,
                  child: _failed
                      ? Center(
                          child: Text('Couldn\'t load the form video.',
                              style: AppTypography.bodySm),
                        )
                      : !ready
                          ? Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: AppColors.accent),
                              ),
                            )
                          : GestureDetector(
                              onTap: () => setState(() =>
                                  controller.value.isPlaying
                                      ? controller.pause()
                                      : controller.play()),
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  VideoPlayer(controller),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: GestureDetector(
                                      onTap: _toggleMute,
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.black.withOpacity(0.45),
                                        ),
                                        child: Icon(
                                          _muted
                                              ? Icons.volume_off_rounded
                                              : Icons.volume_up_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

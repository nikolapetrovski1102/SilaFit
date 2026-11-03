import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/mascot/celebrating_ram.dart';
import '../../core/widgets/mascot/mascot_dialog.dart';
import '../../core/widgets/mascot/mascot_empty_state.dart';
import '../../core/widgets/mascot/mascot_toast.dart';
import '../../core/widgets/mascot/ram_mascot.dart';
import '../../core/widgets/mascot/talking_mascot.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_ambient_backdrop.dart';
import '../../core/widgets/silen_button.dart';
import '../onboarding/onboarding_controller.dart';
import '../onboarding/onboarding_mascot_lines.dart';

/// Playground that fires every mascot moment on demand, so
/// the art and the animations can be reviewed without finishing a workout,
/// building a 7-day streak or replaying onboarding. Opened from the
/// Preview section of Settings (see `_showMascotPreview` there).
///
/// Everything here uses the real widgets with the same arguments as their
/// call sites, so what you see is what users see.
class MascotPreviewScreen extends StatefulWidget {
  const MascotPreviewScreen({super.key});

  @override
  State<MascotPreviewScreen> createState() => _MascotPreviewScreenState();
}

class _MascotPreviewScreenState extends State<MascotPreviewScreen> {
  int _stageRun = 0;
  int _lineIndex = 0;
  bool _reduceMotion = false;

  static final List<MascotLine> _lines = [
    for (final step in OnboardingStep.values)
      if (mascotLineFor(step) case final line?) line,
  ];

  // Same dialogs as the end of ActiveWorkoutTrackerScreen._finishWorkout.
  void _workoutComplete() => MascotDialog.show(
        context,
        pose: RamArt.charging,
        title: 'Workout complete',
        message: 'Nice work. Your session has been logged.',
        showConfetti: true,
      );

  void _streakMilestone() => MascotDialog.show(
        context,
        pose: RamArt.standing,
        title: '7-day streak!',
        message: "You're on fire - 7 days in a row. Keep it going.",
        showConfetti: true,
      );

  void _savedOffline() => MascotDialog.show(
        context,
        pose: RamArt.charging,
        title: 'Workout complete',
        message:
            "Nice work. Saved on your phone - it'll upload by itself when you're back online.",
        showConfetti: true,
      );

  void _plainDialog() => MascotDialog.show(
        context,
        pose: RamArt.smug,
        title: 'Plain mascot dialog',
        message: 'No celebration - the static pose for alerts and notices.',
        actionLabel: 'Got it',
      );

  void _toast(RamArt pose) => MascotToast.show(
        context,
        pose: pose,
        message: 'Toast with the ${pose.name} pose.',
      );

  @override
  Widget build(BuildContext context) {
    // Only the inline previews follow this switch. Dialogs and toasts open
    // in their own route or overlay and follow the device setting.
    final inline = MediaQuery.of(context).copyWith(
        disableAnimations:
            _reduceMotion || MediaQuery.disableAnimationsOf(context));

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: SilenAmbientBackdrop()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xs, AppSpacing.xs, AppSpacing.marginMobile, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded,
                            color: AppColors.onSurface),
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text('Mascot preview',
                            style: AppTypography.bodyMd
                                .copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: MediaQuery(
                    data: inline,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.marginMobile,
                          vertical: AppSpacing.lg),
                      children: [
                        _reduceMotionSwitch(),
                        ..._section('Celebration dialogs', [
                          _button('Workout complete', _workoutComplete),
                          _button('7-day streak milestone', _streakMilestone),
                          _button('Workout saved offline', _savedOffline),
                          _button('Plain dialog', _plainDialog,
                              secondary: true),
                        ]),
                        ..._section('Celebration stage (tap Sila to replay)', [
                          Center(
                            child: CelebratingRam(
                                key: ValueKey('$_stageRun-$_reduceMotion'),
                                size: 150),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _button('Restart', () => setState(() => _stageRun++),
                              secondary: true),
                        ]),
                        ..._section('Toasts', [
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: [
                              for (final pose in RamArt.values)
                                ActionChip(
                                  label: Text(pose.name),
                                  onPressed: () => _toast(pose),
                                ),
                            ],
                          ),
                        ]),
                        ..._section('Onboarding talking mascot', [
                          TalkingMascot(line: _lines[_lineIndex]),
                          const SizedBox(height: AppSpacing.md),
                          _button(
                            'Next line ${_lineIndex + 1}/${_lines.length}',
                            () => setState(() =>
                                _lineIndex = (_lineIndex + 1) % _lines.length),
                            secondary: true,
                          ),
                        ]),
                        ..._section('Onboarding intro', [
                          const Center(
                              child: RamMascot(RamArt.laughing, size: 150)),
                        ]),
                        ..._section('Today: rest-day card art', [
                          Row(
                            children: [
                              Expanded(
                                child: Text('REST DAY',
                                    style: AppTypography.headlineLg),
                              ),
                              const RamMascot(RamArt.sleepy, size: 68),
                            ],
                          ),
                        ]),
                        ..._section('Empty state', [
                          const MascotEmptyState(
                            title: 'No splits yet',
                            message: 'Empty states currently show text only.',
                          ),
                        ]),
                        ..._section('All art', [
                          GridView.count(
                            crossAxisCount: 3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: AppSpacing.sm,
                            crossAxisSpacing: AppSpacing.sm,
                            childAspectRatio: 0.82,
                            children: [
                              for (final art in RamArt.values)
                                Column(
                                  children: [
                                    Expanded(child: RamMascot(art, size: 96)),
                                    const SizedBox(height: AppSpacing.xxs),
                                    Text(art.name,
                                        style: AppTypography.bodySm.copyWith(
                                            color: AppColors.onSurfaceVariant)),
                                  ],
                                ),
                            ],
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reduceMotionSwitch() => SectionCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Simulate reduced motion', style: AppTypography.bodyMd),
                  const SizedBox(height: 2),
                  Text('Inline previews only; dialogs follow the device',
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            Switch(
              value: _reduceMotion,
              onChanged: (v) => setState(() => _reduceMotion = v),
              activeThumbColor: AppColors.onAccent,
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.surfaceContainerHigh,
            ),
          ],
        ),
      );

  List<Widget> _section(String title, List<Widget> children) => [
        const SizedBox(height: AppSpacing.lg),
        SectionEyebrow(title),
        const SizedBox(height: AppSpacing.sm),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ];

  Widget _button(String label, VoidCallback onPressed,
          {bool secondary = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: secondary
            ? SecondaryPillButton(label: label, onPressed: onPressed)
            : PrimaryPillButton(label: label, onPressed: onPressed),
      );
}

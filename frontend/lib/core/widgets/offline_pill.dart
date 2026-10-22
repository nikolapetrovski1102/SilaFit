import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Small status pill that fades in while [offline] is true or writes made
/// with no signal are still waiting to upload ([pendingCount]) - tells the
/// lifter the screen is showing saved data and their sets aren't lost,
/// rather than leaving them to wonder. Purely informational, so it never
/// takes taps.
class OfflinePill extends StatelessWidget {
  final ValueListenable<bool> offline;
  final ValueListenable<int>? pendingCount;

  const OfflinePill({super.key, required this.offline, this.pendingCount});

  static const _noPending = _ZeroListenable();

  /// What the pill says, or null when there's nothing to say.
  static String? label({required bool offline, required int pending}) {
    final changes = pending == 1 ? '1 change' : '$pending changes';
    if (offline && pending > 0) return 'Offline · $changes saved on phone';
    if (offline) return 'Offline · showing saved data';
    if (pending > 0) return 'Syncing $changes…';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<bool>(
        valueListenable: offline,
        builder: (context, isOffline, _) => ValueListenableBuilder<int>(
          valueListenable: pendingCount ?? _noPending,
          builder: (context, pending, _) {
            final text = label(offline: isOffline, pending: pending);
            return AnimatedOpacity(
              opacity: text == null ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          isOffline
                              ? Icons.cloud_off_rounded
                              : Icons.cloud_upload_outlined,
                          size: 14,
                          color: AppColors.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.xs),
                      Text(text ?? '',
                          style: AppTypography.labelSm
                              .copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ZeroListenable implements ValueListenable<int> {
  const _ZeroListenable();

  @override
  int get value => 0;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

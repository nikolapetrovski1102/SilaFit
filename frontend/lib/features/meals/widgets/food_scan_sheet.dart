import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/silen_button.dart';
import '../../splits/widgets/ink_field.dart';
import '../meal_controller.dart';
import '../meal_models.dart';
import 'food_picker_sheet.dart';

/// Sends [photo] (an already downsized JPEG) for an AI ingredient and macro
/// estimate, then lets the user choose what to add. The photo stays on screen
/// with a sweeping scan line while the model works (usually 10-30 s).
///
/// Returns the chosen items ready to drop into the meal, or null if the sheet
/// was dismissed. [onQuota] gets the day's updated allowance whenever the
/// server reports it, so the caller's "N left today" stays true even when the
/// user backs out of the results.
Future<List<MealLogItem>?> showFoodScanSheet(
  BuildContext context, {
  required MealController controller,
  required Uint8List photo,
  String? mealName,
  ValueChanged<FoodScanQuota>? onQuota,
}) {
  return showModalBottomSheet<List<MealLogItem>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _FoodScanView(
        controller: controller,
        photo: photo,
        mealName: mealName,
        onQuota: onQuota,
        onDone: (items) => Navigator.of(sheetContext).pop(items),
      ),
    ),
  );
}

class _FoodScanView extends StatefulWidget {
  final MealController controller;
  final Uint8List photo;
  final String? mealName;
  final ValueChanged<FoodScanQuota>? onQuota;
  final ValueChanged<List<MealLogItem>> onDone;

  const _FoodScanView({
    required this.controller,
    required this.photo,
    required this.mealName,
    required this.onQuota,
    required this.onDone,
  });

  @override
  State<_FoodScanView> createState() => _FoodScanViewState();
}

class _FoodScanViewState extends State<_FoodScanView> {
  FoodScanResult? _result;
  String? _error;

  /// Only failures that didn't use a scan are worth retrying in place - a
  /// spent allowance or lost access won't change by tapping again.
  bool _canRetry = false;

  /// Which results are ticked. Items the AI only assumed (cooking oil,
  /// dressing) start unticked so the user opts in to them.
  final _selected = <int>{};

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _result = null;
      _error = null;
    });
    try {
      final result = await widget.controller
          .scanFood(widget.photo, mealName: widget.mealName);
      widget.onQuota?.call(result.quota);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _result = result;
        _selected
          ..clear()
          ..addAll([
            for (var i = 0; i < result.items.length; i++)
              if (!result.items[i].isAssumed) i
          ]);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _canRetry = !e.isTooManyRequests &&
            !e.isForbidden &&
            !e.isAiConsentRequired &&
            e.statusCode != 400;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = ApiException.genericMessage;
        _canRetry = true;
      });
    }
  }

  void _toggle(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(index)) _selected.add(index);
    });
  }

  void _addSelected() {
    final items = _result!.items;
    widget.onDone([
      for (var i = 0; i < items.length; i++)
        if (_selected.contains(i)) items[i].toLogItem()
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final scanning = result == null && _error == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile, AppSpacing.md,
          AppSpacing.marginMobile, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ScanPhoto(photo: widget.photo, scanning: scanning),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: AnimatedSwitcher(
              duration: kInkQuick,
              child: scanning
                  ? const _ScanningLabel(key: ValueKey('scanning'))
                  : _error != null
                      ? _ScanError(
                          key: const ValueKey('error'),
                          message: _error!,
                        )
                      : _ScanResults(
                          key: const ValueKey('results'),
                          result: result!,
                          selected: _selected,
                          onToggle: _toggle,
                        ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildAction(scanning, result),
        ],
      ),
    );
  }

  Widget _buildAction(bool scanning, FoodScanResult? result) {
    if (scanning) {
      return SecondaryPillButton(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(),
      );
    }
    if (_error != null) {
      return _canRetry
          ? PrimaryPillButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onPressed: _scan,
            )
          : SecondaryPillButton(
              label: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            );
    }
    if (result == null || !result.isFood || result.items.isEmpty) {
      return SecondaryPillButton(
        label: 'Close',
        onPressed: () => Navigator.of(context).pop(),
      );
    }
    final count = _selected.length;
    return PrimaryPillButton(
      label: count == 0
          ? 'Choose ingredients'
          : 'Add $count ingredient${count == 1 ? '' : 's'}',
      icon: Icons.add_rounded,
      onPressed: count == 0 ? null : _addSelected,
    );
  }
}

/// The photo, with a soft scan line sweeping over it while the AI works.
class _ScanPhoto extends StatefulWidget {
  final Uint8List photo;
  final bool scanning;

  const _ScanPhoto({required this.photo, required this.scanning});

  @override
  State<_ScanPhoto> createState() => _ScanPhotoState();
}

class _ScanPhotoState extends State<_ScanPhoto>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.scanning) _sweep.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_ScanPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scanning && !_sweep.isAnimating) {
      _sweep.repeat(reverse: true);
    } else if (!widget.scanning && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: kInkMorph,
      curve: Curves.easeOutCubic,
      height: widget.scanning ? 300 : 140,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(widget.photo, fit: BoxFit.cover),
            AnimatedOpacity(
              opacity: widget.scanning ? 1 : 0,
              duration: kInkQuick,
              child: AnimatedBuilder(
                animation: _sweep,
                builder: (context, _) => CustomPaint(
                  painter: _SweepPainter(
                      Curves.easeInOut.transform(_sweep.value),
                      AppColors.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  final double t;
  final Color color;

  _SweepPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size,
        Paint()..color = Colors.black.withValues(alpha: 0.25));
    final y = size.height * t;
    const glow = 60.0;
    final band = Rect.fromLTWH(0, y - glow, size.width, glow);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.35)],
        ).createShader(band),
    );
    canvas.drawRect(
        Rect.fromLTWH(0, y - 1, size.width, 2), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.t != t || old.color != color;
}

class _ScanningLabel extends StatelessWidget {
  const _ScanningLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reading your meal…', style: AppTypography.headlineSm),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Picking out each ingredient and estimating its portion. This '
          'usually takes 10-30 seconds.',
          style:
              AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ScanError extends StatelessWidget {
  final String message;

  const _ScanError({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, color: AppColors.error, size: 28),
        const SizedBox(height: AppSpacing.xs),
        Text(message, style: AppTypography.bodyMd),
      ],
    );
  }
}

class _ScanResults extends StatelessWidget {
  final FoodScanResult result;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  const _ScanResults({
    super.key,
    required this.result,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final muted =
        AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant);
    if (!result.isFood || result.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No food found', style: AppTypography.headlineSm),
          const SizedBox(height: AppSpacing.xs),
          Text(
            result.notes.isNotEmpty
                ? result.notes
                : 'Try a clearer photo of the plate from above.',
            style: muted,
          ),
        ],
      );
    }

    final items = result.items;
    final kcal = [
      for (var i = 0; i < items.length; i++)
        if (selected.contains(i))
          items[i].caloriesKcal * items[i].estimatedGrams / 100
    ].fold<double>(0, (a, b) => a + b);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text(result.dishName, style: AppTypography.headlineSm),
        const SizedBox(height: AppSpacing.xxs),
        Text('${kcal.round()} kcal selected · AI estimate, adjust grams after',
            style: muted),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ScanItemRow(
              item: items[i],
              selected: selected.contains(i),
              onTap: () => onToggle(i),
            ),
          ),
        if (result.notes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(result.notes, style: muted),
        ],
      ],
    );
  }
}

class _ScanItemRow extends StatelessWidget {
  final FoodScanItem item;
  final bool selected;
  final VoidCallback onTap;

  const _ScanItemRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final f = item.estimatedGrams / 100;
    final muted =
        AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant);
    return Material(
      color: selected
          ? AppColors.accent.withValues(alpha: 0.10)
          : AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: selected ? AppColors.accent : AppColors.outline,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyMd,
                          ),
                        ),
                        if (item.isAssumed || item.confidence == 'low') ...[
                          const SizedBox(width: AppSpacing.xs),
                          _Tag(item.isAssumed ? 'likely' : 'unsure'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    MacroLine(
                      proteinG: item.proteinG * f,
                      carbsG: item.carbohydrateG * f,
                      fatsG: item.fatG * f,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${(item.caloriesKcal * f).round()} kcal',
                      style: AppTypography.bodyMd),
                  Text('${item.estimatedGrams.round()} g', style: muted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;

  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(label,
          style: AppTypography.labelSm.copyWith(color: AppColors.secondary)),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

enum MacroKind {
  calories('Calories', 'kcal', 900),
  protein('Protein', 'g', 100),
  carbs('Carbs', 'g', 100),
  fat('Fat', 'g', 100),
  fiber('Fiber', 'g', 100),
  sugar('Sugar', 'g', 100),
  sodium('Sodium', 'mg', 40000);

  final String label;
  final String unit;

  /// Largest value that makes sense per 100 g - mirrors FoodService's
  /// custom-food validation so the form catches it before the server does.
  final double maxPer100g;

  const MacroKind(this.label, this.unit, this.maxPer100g);
}

/// One row of the custom-food form: a typed amount and, once there is one,
/// which nutrient it is.
class MacroEntry {
  final TextEditingController text = TextEditingController();
  MacroKind? kind;

  double? get value {
    final parsed = double.tryParse(text.text.trim().replaceAll(',', '.'));
    return parsed == null || parsed < 0 ? null : parsed;
  }

  void dispose() => text.dispose();
}

/// Amount-first macro entry: the number field leads the row, and the
/// nutrient selector slides/fades in at the end of the same row only after a
/// number has been typed - "30" first, then "Protein".
class MacroAmountRow extends StatefulWidget {
  final MacroEntry entry;

  /// Nutrients already used by other rows; hidden from this row's selector.
  final Set<MacroKind> taken;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const MacroAmountRow({
    super.key,
    required this.entry,
    required this.taken,
    required this.onChanged,
    this.onRemove,
  });

  @override
  State<MacroAmountRow> createState() => _MacroAmountRowState();
}

class _MacroAmountRowState extends State<MacroAmountRow> {
  MacroEntry get _entry => widget.entry;

  bool get _hasNumber => _entry.value != null;

  void _onTextChanged(String _) {
    setState(() {});
    widget.onChanged();
  }

  void _select(MacroKind kind) {
    HapticFeedback.selectionClick();
    setState(() => _entry.kind = kind);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final kind = _entry.kind;
    final value = _entry.value;
    final tooHigh = kind != null && value != null && value > kind.maxPer100g;
    final options = [
      for (final k in MacroKind.values)
        if (k == kind || !widget.taken.contains(k)) k,
    ];

    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.inset),
        border: Border.all(
            color: tooHigh ? AppColors.error : Colors.transparent),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: TextField(
              controller: _entry.text,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: AppTypography.headlineSm,
              onChanged: _onTextChanged,
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: AppTypography.headlineSm
                    .copyWith(color: AppColors.onSurfaceVariant.withValues(alpha: 0.4)),
                suffixText: kind?.unit,
                suffixStyle: AppTypography.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(0.25, 0), end: Offset.zero)
                      .animate(animation),
                  child: child,
                ),
              ),
              child: !_hasNumber
                  ? const SizedBox.expand(key: ValueKey('empty'))
                  : ListView(
                      key: const ValueKey('kinds'),
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs),
                      children: [
                        for (final k in options)
                          Padding(
                            padding:
                                const EdgeInsets.only(right: AppSpacing.xxs),
                            child: _KindChip(
                              label: k.label,
                              selected: k == kind,
                              // Nudge the user to pick one until they have.
                              highlight: kind == null,
                              onTap: () => _select(k),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          if (widget.onRemove != null)
            IconButton(
              onPressed: widget.onRemove,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded,
                  size: 18, color: AppColors.onSurfaceVariant),
            )
          else
            const SizedBox(width: AppSpacing.xs),
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool highlight;
  final VoidCallback onTap;

  const _KindChip({
    required this.label,
    required this.selected,
    required this.highlight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? AppColors.accent
        : highlight
            ? AppColors.accent.withValues(alpha: 0.12)
            : AppColors.surfaceContainerHighest;
    final fg = selected
        ? AppColors.onAccent
        : highlight
            ? AppColors.accent
            : AppColors.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(label, style: AppTypography.labelSm.copyWith(color: fg)),
      ),
    );
  }
}

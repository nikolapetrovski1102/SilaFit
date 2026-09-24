import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/section_eyebrow.dart';
import '../../../core/widgets/silen_button.dart';
import '../meal_controller.dart';
import '../meal_models.dart';
import 'macro_amount_row.dart';

/// Opens the "new food" form on its own - for when the catalog search has
/// no match. Returns the created food (per 100 g), or null if dismissed.
Future<FoodItem?> showCustomFoodSheet(BuildContext context,
    {required MealController controller, String initialName = ''}) {
  return showModalBottomSheet<FoodItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: _CustomFoodForm(
          controller: controller,
          initialName: initialName,
          onBack: () => Navigator.of(sheetContext).pop(),
          onCreated: (food) => Navigator.of(sheetContext).pop(food),
        ),
      ),
    ),
  );
}

/// Opens just the amount step for a food already in the meal, so a tap on
/// its grams chip in the tracker edits it in place.
Future<double?> showGramsSheet(BuildContext context,
    {required String title, required double initialGrams, FoodItem? food}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.marginMobile,
          AppSpacing.marginMobile,
          AppSpacing.marginMobile,
          AppSpacing.md + MediaQuery.of(sheetContext).viewInsets.bottom),
      child: _GramsEditor(
        food: food,
        title: title,
        initialGrams: initialGrams,
        actionLabel: 'Update',
        onConfirm: (grams) => Navigator.of(sheetContext).pop(grams),
      ),
    ),
  );
}

class _SheetBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SheetBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.arrow_back_rounded,
              size: 20, color: AppColors.onSurface),
        ),
      ),
    );
  }
}

String _fmt(double v) =>
    v >= 100 || v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Protein / carbs / fat as three colour-keyed values on one line - the same
/// colours the Nutrition screen's macro bars use.
class MacroLine extends StatelessWidget {
  final double proteinG;
  final double carbsG;
  final double fatsG;

  const MacroLine({
    super.key,
    required this.proteinG,
    required this.carbsG,
    required this.fatsG,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: 2,
      children: [
        _MacroDot(label: 'P', value: proteinG, color: AppColors.accent),
        _MacroDot(label: 'C', value: carbsG, color: AppColors.tertiaryContainer),
        _MacroDot(label: 'F', value: fatsG, color: AppColors.secondary),
      ],
    );
  }
}

class _MacroDot extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _MacroDot(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text('$label ${_fmt(value)}g',
            style: AppTypography.labelSm
                .copyWith(color: AppColors.onSurfaceVariant)),
      ],
    );
  }
}

/// The amount step: a big grams readout with +/- steppers (the workout
/// tracker's weight/reps pattern), quick serving chips, and the food's
/// macros rescaled live to the chosen amount.
class _GramsEditor extends StatefulWidget {
  final FoodItem? food;
  final String title;
  final double initialGrams;
  final String actionLabel;
  final ValueChanged<double> onConfirm;

  const _GramsEditor({
    this.food,
    required this.title,
    required this.initialGrams,
    required this.actionLabel,
    required this.onConfirm,
  });

  @override
  State<_GramsEditor> createState() => _GramsEditorState();
}

class _GramsEditorState extends State<_GramsEditor> {
  static const _min = 1.0;
  static const _max = 5000.0;
  static const _step = 10.0;

  late final _textController =
      TextEditingController(text: _fmt(widget.initialGrams));

  double get _grams {
    final parsed = double.tryParse(_textController.text.trim().replaceAll(',', '.')) ?? 0;
    return parsed.clamp(0, _max).toDouble();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _set(double grams) {
    HapticFeedback.selectionClick();
    final clamped = grams.clamp(_min, _max).toDouble();
    setState(() => _textController.text = _fmt(clamped));
  }

  @override
  Widget build(BuildContext context) {
    final food = widget.food;
    final grams = _grams;
    final scaled = food == null ? null : MealLogItem.fromFood(food, grams);
    final quick = <double>{
      if (food?.servingSizeG != null && food!.servingSizeG! > 0)
        food.servingSizeG!,
      50,
      100,
      150,
      200,
    }.toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('HOW MUCH?',
            style: AppTypography.labelCaps.copyWith(color: AppColors.accent)),
        const SizedBox(height: 4),
        Text(widget.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.headlineSm),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            _RoundStep(
                icon: Icons.remove_rounded, onTap: () => _set(grams - _step)),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  IntrinsicWidth(
                    child: TextField(
                      controller: _textController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: AppTypography.displayStatMobile,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('g',
                      style: AppTypography.bodyLg
                          .copyWith(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            _RoundStep(
                icon: Icons.add_rounded, onTap: () => _set(grams + _step)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final g in quick)
              PillChip(
                label: g == food?.servingSizeG
                    ? '1 serving · ${_fmt(g)} g'
                    : '${_fmt(g)} g',
                selected: g == grams,
                onTap: () => _set(g),
              ),
          ],
        ),
        if (scaled != null) ...[
          const SizedBox(height: AppSpacing.xl),
          NutrientGrid(item: scaled),
        ],
        const SizedBox(height: AppSpacing.xl),
        PrimaryPillButton(
          label: widget.actionLabel,
          icon: Icons.check_rounded,
          height: 56,
          onPressed: grams >= _min ? () => widget.onConfirm(grams) : null,
        ),
      ],
    );
  }
}

class _RoundStep extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundStep({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: AppColors.onSurface),
      ),
    );
  }
}

/// Every nutrient of one food at its logged amount: calories and the three
/// macros as big stats, then fiber/sugar/sodium when the source has them.
class NutrientGrid extends StatelessWidget {
  final MealLogItem item;

  const NutrientGrid({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final extras = <(String, String)>[
      if (item.fiberG != null) ('Fiber', '${_fmt(item.fiberG!)} g'),
      if (item.sugarG != null) ('Sugar', '${_fmt(item.sugarG!)} g'),
      if (item.sodiumMg != null) ('Sodium', '${_fmt(item.sodiumMg!)} mg'),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Stat(value: _fmt(item.caloriesKcal), label: 'KCAL'),
              _Stat(
                  value: '${_fmt(item.proteinG)}g',
                  label: 'PROTEIN',
                  color: AppColors.accent),
              _Stat(
                  value: '${_fmt(item.carbsG)}g',
                  label: 'CARBS',
                  color: AppColors.tertiaryContainer),
              _Stat(
                  value: '${_fmt(item.fatsG)}g',
                  label: 'FAT',
                  color: AppColors.secondary),
            ],
          ),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(height: 1, color: AppColors.outlineVariant),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (final (label, value) in extras)
                  Expanded(
                    child: Column(
                      children: [
                        Text(value, style: AppTypography.labelSm),
                        Text(label.toUpperCase(),
                            style: AppTypography.labelCaps
                                .copyWith(fontSize: 9)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;

  const _Stat({required this.value, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: AppTypography.numericUnit
                  .copyWith(color: AppColors.onSurface)),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (color != null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
              ],
              Text(label,
                  style: AppTypography.labelCaps.copyWith(fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Add a new food": name, optional brand and serving size, then the label's
/// values per 100 g entered as amount-first rows (see [MacroAmountRow]).
class _CustomFoodForm extends StatefulWidget {
  final MealController controller;
  final String initialName;
  final VoidCallback onBack;
  final ValueChanged<FoodItem> onCreated;

  const _CustomFoodForm({
    required this.controller,
    required this.initialName,
    required this.onBack,
    required this.onCreated,
  });

  @override
  State<_CustomFoodForm> createState() => _CustomFoodFormState();
}

class _CustomFoodFormState extends State<_CustomFoodForm> {
  late final _nameController = TextEditingController(text: widget.initialName);
  final _brandController = TextEditingController();
  final _servingController = TextEditingController();
  final List<MacroEntry> _entries = [MacroEntry()];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _servingController.dispose();
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  Set<MacroKind> get _usedKinds =>
      {for (final e in _entries) if (e.kind != null) e.kind!};

  double? _valueOf(MacroKind kind) {
    for (final e in _entries) {
      if (e.kind == kind && e.value != null) return e.value;
    }
    return null;
  }

  void _onEntryChanged(MacroEntry entry) {
    setState(() {
      // Keep one blank row at the end while there are macro types left, so
      // the next value can be typed straight away.
      final last = _entries.last;
      if (last.kind != null &&
          last.value != null &&
          _usedKinds.length < MacroKind.values.length) {
        _entries.add(MacroEntry());
      }
    });
  }

  void _remove(MacroEntry entry) {
    setState(() {
      _entries.remove(entry);
      entry.dispose();
      if (_entries.isEmpty) _entries.add(MacroEntry());
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the food a name.');
      return;
    }
    for (final e in _entries) {
      final v = e.value;
      if (v == null) continue;
      if (e.kind == null) {
        setState(() => _error = 'Pick what ${_fmt(v)} is.');
        return;
      }
      if (v > e.kind!.maxPer100g) {
        setState(() => _error =
            '${e.kind!.label} can\'t be more than ${_fmt(e.kind!.maxPer100g)} '
            '${e.kind!.unit} per 100 g.');
        return;
      }
    }
    final kcal = _valueOf(MacroKind.calories);
    final protein = _valueOf(MacroKind.protein);
    final carbs = _valueOf(MacroKind.carbs);
    final fat = _valueOf(MacroKind.fat);
    if ((kcal ?? 0) == 0 && (protein ?? 0) == 0 && (carbs ?? 0) == 0 &&
        (fat ?? 0) == 0) {
      setState(() => _error = 'Enter at least calories or one macro.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final food = await widget.controller.createCustomFood(
        name: name,
        brandName: _brandController.text.trim().isEmpty
            ? null
            : _brandController.text.trim(),
        servingSizeG: double.tryParse(
            _servingController.text.trim().replaceAll(',', '.')),
        // Calories fall back to the Atwater estimate when only macros were
        // entered, so the food still counts toward the day's energy.
        caloriesKcal: kcal ??
            ((protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9),
        proteinG: protein ?? 0,
        carbohydrateG: carbs ?? 0,
        fatG: fat ?? 0,
        fiberG: _valueOf(MacroKind.fiber),
        sugarG: _valueOf(MacroKind.sugar),
        sodiumMg: _valueOf(MacroKind.sodium),
      );
      if (!mounted) return;
      widget.onCreated(food);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } catch (_) {
      if (mounted) setState(() => _error = ApiException.genericMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                AppSpacing.sm, AppSpacing.marginMobile, AppSpacing.md),
            children: [
              _SheetBackButton(onTap: widget.onBack),
              const SizedBox(height: AppSpacing.xs),
              Text('NEW FOOD',
                  style: AppTypography.labelCaps
                      .copyWith(color: AppColors.accent)),
              const SizedBox(height: 4),
              Text('Add it from the label', style: AppTypography.headlineSm),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                style: AppTypography.bodyMd,
                decoration: const InputDecoration(labelText: 'Food name'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _brandController,
                      style: AppTypography.bodyMd,
                      decoration:
                          const InputDecoration(labelText: 'Brand (optional)'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _servingController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: AppTypography.bodyMd,
                      decoration: const InputDecoration(
                          labelText: 'Serving', suffixText: 'g'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('NUTRITION PER 100 G', style: AppTypography.labelCaps),
              const SizedBox(height: 2),
              Text('Type a value, then pick what it is.',
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.sm),
              for (final entry in _entries)
                Padding(
                  key: ObjectKey(entry),
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: MacroAmountRow(
                    entry: entry,
                    taken: _usedKinds,
                    onChanged: () => _onEntryChanged(entry),
                    onRemove: _entries.length > 1 ? () => _remove(entry) : null,
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!,
                    style:
                        AppTypography.bodySm.copyWith(color: AppColors.error)),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
              AppSpacing.sm, AppSpacing.marginMobile, AppSpacing.md),
          child: PrimaryPillButton(
            label: 'Save food',
            icon: Icons.check_rounded,
            isLoading: _saving,
            onPressed: _save,
          ),
        ),
      ],
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import 'meal_controller.dart';
import 'meal_models.dart';
import 'widgets/calorie_ring.dart';

const _kCaloriesMin = 1000.0;
const _kCaloriesMax = 5000.0;
const _kCaloriesStep = 10.0;
const _kGramsStep = 1.0;

/// Pushes the targets editor; the Nutrition screen's calorie ring flies up
/// into it as a Hero while everything else fades through.
Future<void> openNutritionTargets(
    BuildContext context, MealController controller) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 520),
    reverseTransitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (_, __, ___) => NutritionTargetsScreen(controller: controller),
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  ));
}

/// The user's own daily calorie and macro targets: the calorie ring big on
/// top (live - it shows today's intake against the target being set), and a
/// slider each for calories, protein, carbs and fat beneath it.
///
/// The sliders are linked so the numbers always add up: moving calories
/// scales the three macros by the same factor (keeping the split), moving a
/// macro re-totals calories from 4 / 4 / 9 kcal per gram.
class NutritionTargetsScreen extends StatefulWidget {
  final MealController controller;

  const NutritionTargetsScreen({super.key, required this.controller});

  @override
  State<NutritionTargetsScreen> createState() => _NutritionTargetsScreenState();
}

enum _Macro { protein, carbs, fat }

extension on _Macro {
  String get label => switch (this) {
        _Macro.protein => 'Protein',
        _Macro.carbs => 'Carbs',
        _Macro.fat => 'Fat',
      };

  double get kcalPerGram => this == _Macro.fat ? 9 : 4;

  double get max => switch (this) {
        _Macro.protein => 400,
        _Macro.carbs => 700,
        _Macro.fat => 250,
      };

  Color get color => switch (this) {
        _Macro.protein => AppColors.accent,
        _Macro.carbs => AppColors.tertiaryContainer,
        _Macro.fat => AppColors.secondary,
      };
}

class _NutritionTargetsScreenState extends State<NutritionTargetsScreen> {
  late final NutritionTargets _initial;
  late final int _consumed;
  late final double _initialProgress;

  late double _calories;
  late final Map<_Macro, double> _grams;
  late final double _caloriesMax;
  late final Map<_Macro, double> _gramsMax;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final day = widget.controller.state.data;
    _initial = day?.targets ??
        const NutritionTargets(
            targetCalories: 2000,
            targetProteinG: 150,
            targetCarbsG: 200,
            targetFatsG: 67);
    _consumed = day?.consumedCalories ?? 0;
    _calories = _initial.targetCalories
        .toDouble()
        .clamp(_kCaloriesMin, double.infinity);
    _grams = {
      _Macro.protein: _initial.targetProteinG.toDouble(),
      _Macro.carbs: _initial.targetCarbsG.toDouble(),
      _Macro.fat: _initial.targetFatsG.toDouble(),
    };
    // A target set elsewhere may sit beyond the default range - stretch the
    // slider to it rather than clamp it away.
    _caloriesMax = math.max(_kCaloriesMax, _calories);
    _gramsMax = {
      for (final m in _Macro.values) m: math.max(m.max, _grams[m]!),
    };
    _initialProgress = _progressFor(_initial.targetCalories.toDouble());
  }

  double _progressFor(double target) =>
      target <= 0 ? 0 : (_consumed / target).clamp(0.0, 1.0);

  double get _macroKcal =>
      _Macro.values.fold(0.0, (sum, m) => sum + _grams[m]! * m.kcalPerGram);

  NutritionTargets get _current => NutritionTargets(
        targetCalories: _calories.round(),
        targetProteinG: _grams[_Macro.protein]!.round(),
        targetCarbsG: _grams[_Macro.carbs]!.round(),
        targetFatsG: _grams[_Macro.fat]!.round(),
      );

  bool get _dirty {
    final c = _current;
    return c.targetCalories != _initial.targetCalories ||
        c.targetProteinG != _initial.targetProteinG ||
        c.targetCarbsG != _initial.targetCarbsG ||
        c.targetFatsG != _initial.targetFatsG;
  }

  /// A light tick every [every] units crossed, not on every step - a
  /// 10 kcal slider would otherwise buzz continuously.
  void _tick(double before, double after, double every) {
    if ((before / every).floor() != (after / every).floor()) {
      HapticFeedback.selectionClick();
    }
  }

  void _setCalories(double value) {
    final next = (value / _kCaloriesStep).round() * _kCaloriesStep;
    if (next == _calories) return;
    _tick(_calories, next, 100);
    setState(() {
      final total = _macroKcal;
      if (total > 0) {
        final factor = next / total;
        for (final m in _Macro.values) {
          _grams[m] =
              (_grams[m]! * factor).roundToDouble().clamp(0, _gramsMax[m]!);
        }
      }
      _calories = next;
    });
  }

  void _setGrams(_Macro macro, double value) {
    final next = (value / _kGramsStep).round() * _kGramsStep;
    if (next == _grams[macro]) return;
    _tick(_grams[macro]!, next, 10);
    setState(() {
      _grams[macro] = next;
      final total = (_macroKcal / _kCaloriesStep).round() * _kCaloriesStep;
      _calories = total.clamp(_kCaloriesMin, _caloriesMax);
    });
  }

  Future<void> _typeCalories() async {
    final input = TextEditingController(text: '${_calories.round()}');
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          final parsed = double.tryParse(input.text.trim());
          Navigator.of(dialogContext).pop(parsed);
        }

        return AlertDialog(
          backgroundColor: AppColors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card)),
          title: Text('Daily calories', style: AppTypography.headlineSm),
          content: TextField(
            controller: input,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(5),
            ],
            style: AppTypography.headlineMd,
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              suffixText: 'kcal',
              helperText:
                  '${_kCaloriesMin.round()} - ${_caloriesMax.round()} kcal',
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel', style: AppTypography.bodyMd),
            ),
            TextButton(
              onPressed: submit,
              child: Text('Set',
                  style:
                      AppTypography.bodyMd.copyWith(color: AppColors.accent)),
            ),
          ],
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
    if (value == null || !mounted) return;
    _setCalories(value.clamp(_kCaloriesMin, _caloriesMax));
  }

  Future<void> _save() async {
    if (!_dirty || _saving) return;
    setState(() => _saving = true);
    final ok = await widget.controller.updateTargets(_current);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(widget.controller.actionError ??
              'Couldn\'t save your targets. Try again.')));
  }

  @override
  Widget build(BuildContext context) {
    final routeAnimation =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;

    // Each block rises in after the ring has mostly landed, a beat apart.
    Widget stagger(int index, Widget child) {
      final start = (0.35 + index * 0.08).clamp(0.0, 0.9);
      final curved = CurvedAnimation(
        parent: routeAnimation,
        curve: Interval(start, 1, curve: Curves.easeOutCubic),
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    }

    final macroKcal = _macroKcal;
    double share(_Macro m) =>
        macroKcal <= 0 ? 0 : _grams[m]! * m.kcalPerGram / macroKcal;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            stagger(
              0,
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs, AppSpacing.xxs, AppSpacing.marginMobile, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: Text('Daily targets',
                          style: AppTypography.headlineSm),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                final ringSize = math.min(
                  constraints.maxWidth * 0.62,
                  math.max(150.0, constraints.maxHeight * 0.36),
                );
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                      AppSpacing.md, AppSpacing.marginMobile, AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox.square(
                          dimension: ringSize,
                          child: CalorieRing.hero(
                            onTap: _typeCalories,
                            ring: CalorieRing(
                              progress: _progressFor(_calories),
                              initialProgress: _initialProgress,
                              value: _calories.round(),
                              label: 'KCAL / DAY',
                              strokeFraction: 0.06,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      stagger(
                        1,
                        Column(
                          children: [
                            Text(
                              _consumed > 0
                                  ? '$_consumed kcal eaten today · tap the ring to type a number'
                                  : 'Tap the ring to type an exact number',
                              textAlign: TextAlign.center,
                              style: AppTypography.labelSm
                                  .copyWith(color: AppColors.onSurfaceVariant),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _SplitBar(
                              shares: [
                                for (final m in _Macro.values)
                                  (share(m), m.color),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      stagger(
                        2,
                        _TargetSlider(
                          label: 'Calories',
                          valueText: '${_calories.round()} kcal',
                          value: _calories,
                          min: _kCaloriesMin,
                          max: _caloriesMax,
                          color: AppColors.accent,
                          onValueTap: _typeCalories,
                          onChanged: _setCalories,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      stagger(3, const SectionEyebrow('Macros')),
                      const SizedBox(height: AppSpacing.sm),
                      for (final (i, m) in _Macro.values.indexed) ...[
                        stagger(
                          4 + i,
                          _TargetSlider(
                            label: m.label,
                            valueText:
                                '${_grams[m]!.round()} g · ${(share(m) * 100).round()}%',
                            value: _grams[m]!,
                            min: 0,
                            max: _gramsMax[m]!,
                            color: m.color,
                            onChanged: (v) => _setGrams(m, v),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
                );
              }),
            ),
            stagger(
              7,
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                    AppSpacing.xs, AppSpacing.marginMobile, AppSpacing.md),
                child: PrimaryPillButton(
                  label: 'Save targets',
                  icon: Icons.check_rounded,
                  isLoading: _saving,
                  onPressed: _dirty ? _save : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The macro split of the target's energy, as one segmented bar.
class _SplitBar extends StatelessWidget {
  final List<(double, Color)> shares;

  const _SplitBar({required this.shares});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            for (final (share, color) in shares)
              if (share > 0)
                Expanded(
                  flex: (share * 1000).round().clamp(1, 1000),
                  child: ColoredBox(color: color),
                ),
          ],
        ),
      ),
    );
  }
}

class _TargetSlider extends StatelessWidget {
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final Color color;
  final ValueChanged<double> onChanged;
  final VoidCallback? onValueTap;

  const _TargetSlider({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
    this.onValueTap,
  });

  @override
  Widget build(BuildContext context) {
    final valueLabel = Text(valueText,
        style: AppTypography.bodyMd.copyWith(
            color: AppColors.highEmphasis, fontWeight: FontWeight.w600));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(label.toUpperCase(), style: AppTypography.labelCaps),
            ),
            if (onValueTap == null)
              valueLabel
            else
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onValueTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    valueLabel,
                    const SizedBox(width: 4),
                    Icon(Icons.edit_rounded,
                        size: 14, color: AppColors.onSurfaceVariant),
                  ],
                ),
              ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: color,
            inactiveTrackColor: AppColors.surfaceContainerHighest,
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.16),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            trackShape: const RoundedRectSliderTrackShape(),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

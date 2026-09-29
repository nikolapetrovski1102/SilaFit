import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/silen_button.dart';
import '../auth/widgets/auth_blob_background.dart';
import '../meals/meal_models.dart';
import '../meals/meal_repository.dart';
import '../splits/widgets/ink_field.dart';
import 'diet_plan_repository.dart';

// Same shape for every diet the wizard creates: a week, one day at a time.
// The diet-plan builder is where the header gets tuned afterwards.
const _kPeriodType = 'Weekly';
const _kDurationDays = 7;

const _kIntro = Duration(milliseconds: 260);

// Line heights of the committed text: the diet name as the title, the
// current day's eyebrow + title beneath it, then (while picking ingredients)
// the meal's eyebrow + title. Titles may wrap to two lines, so the slots
// below them are derived from measured line counts.
const double _kTitleLine = 34; // headlineLg
const double _kEyebrowLine = 14; // labelCaps
const double _kDayLine = 28; // headlineMd
const double _kMealLine = 24; // headlineSm
const int _kMaxTitleLines = 2;

enum _Stage { name, dayTitle, mealName, ingredients, done }

/// Builds a custom diet plan on one screen with one text field (bottom rule
/// only) that keeps focus between steps, so the keyboard never drops - the
/// meal-planning twin of [SplitCreationWizardScreen]:
///
/// 1. the diet's name, as big type - committing it lifts the text up into
///    the screen's title;
/// 2. each day's title, in the same big field - committing it settles under
///    the diet name as the day's heading;
/// 3. that day's meals, one by one: the meal's name (with its slot -
///    Breakfast/Lunch/Dinner/Snack), then its ingredients - the field shrinks
///    to a food search, and tapping a result flies it up into the meal's
///    chips, where a tap sets its grams.
///
/// Saves are optimistic: the diet and each day are created as soon as they
/// are named, and each meal as soon as it's saved, while the requests chain
/// behind (diet -> day -> meal), so nothing waits on the network.
class DietCreationWizardScreen extends StatefulWidget {
  /// How many diets the user already owns - the default name is
  /// "Awesome Diet {existingPlanCount + 1}".
  final int existingPlanCount;

  const DietCreationWizardScreen({super.key, this.existingPlanCount = 0});

  @override
  State<DietCreationWizardScreen> createState() =>
      _DietCreationWizardScreenState();
}

class _Ingredient {
  final FoodItem food;
  double grams;
  bool landed;

  _Ingredient(this.food, {required this.grams, required this.landed});

  double get _f => grams / 100;
  double get calories => food.caloriesKcal * _f;
  double get protein => food.proteinG * _f;
  double get carbs => food.carbohydrateG * _f;
  double get fats => food.fatG * _f;
}

/// A meal saved on the current day - kept with its ingredients so the next
/// day can repeat it.
class _SavedMeal {
  final String title;
  final String mealType;
  final List<({int foodNutritionId, double grams})> items;
  final int calories;

  const _SavedMeal({
    required this.title,
    required this.mealType,
    required this.items,
    required this.calories,
  });
}

class _DietCreationWizardScreenState extends State<DietCreationWizardScreen>
    with TickerProviderStateMixin {
  late final DietPlanRepository _plans;
  late final MealRepository _meals;

  final _input = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _intro;

  /// Fills the field's bottom line in on focus and drains it on blur.
  late final AnimationController _underline;

  _Stage _stage = _Stage.name;
  int _day = 1;
  String? _dietName;
  String? _dayTitle;
  String? _mealTitle;
  String _mealType = kMealTypes.first;

  /// Where the big input sits for the current layout (it follows the
  /// keyboard); captured into the `...From` fields at commit time so the
  /// morphing text starts exactly where the typed text was.
  double _heroTop = 120;
  double _mealInputTop = 120;
  double _titleFrom = 120;
  double _dayFrom = 120;
  double _mealFrom = 120;

  /// Same idea for the big input's auto-scaled type size.
  double _heroSize = kHeroMaxSize;
  double _titleFromSize = kHeroMaxSize;
  double _dayFromSize = kHeroMaxSize;
  double _mealFromSize = kHeroMaxSize;

  /// Bumped when the diet itself fails to save and the flow restarts, so
  /// errors from requests chained off the dead diet are ignored.
  int _generation = 0;
  Future<String?>? _dietId;
  Future<String?>? _dayId;
  final _pending = <Future<void>>[];

  /// Days already built.
  final _completedDays = <int>{};

  /// The current day's saved meals, and the last finished day's (for
  /// "Repeat day N").
  final _dayMeals = <_SavedMeal>[];
  List<_SavedMeal> _previousDayMeals = const [];

  final _ingredients = <_Ingredient>[];
  final _chipKeys = <int, GlobalKey>{};
  final _rowKeys = <int, GlobalKey>{};
  List<FoodItem> _results = const [];
  bool _searching = false;
  Timer? _debounce;
  int _queryToken = 0;

  final _flights = <OverlayEntry>[];
  bool _finishing = false;

  String get _presetName => 'Awesome Diet ${widget.existingPlanCount + 1}';
  String _presetDay(int day) => 'Day $day';

  /// Breakfast, Lunch, Dinner, then Snacks for everything after.
  String get _nextMealType =>
      kMealTypes[_dayMeals.length.clamp(0, kMealTypes.length - 1)];

  @override
  void initState() {
    super.initState();
    _plans = context.read<DietPlanRepository>();
    _meals = context.read<MealRepository>();
    _intro = AnimationController(vsync: this, duration: _kIntro)..forward();
    _underline = AnimationController(vsync: this, duration: kInkMorph);
    _focus.addListener(_onFocusChanged);
    _preset(_presetName);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final flight in _flights) {
      flight.remove();
    }
    _flights.clear();
    _intro.dispose();
    _underline.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focus.hasFocus) {
      _underline.forward();
    } else {
      _underline.reverse();
    }
    // Focus decides whether the search takes over the screen.
    if (mounted) setState(() {});
  }

  /// While a food search is typed the keyboard covers half the screen, so
  /// the titles and the meal's chips fold away and the field rises to the
  /// top, leaving the room to the results. Picking a result drops the
  /// keyboard and everything settles back.
  bool get _searchTakeover =>
      _stage == _Stage.ingredients &&
      _focus.hasFocus &&
      _input.text.trim().isNotEmpty;

  /// Fills the field with [text] fully selected, so typing replaces it and
  /// submitting straight away keeps it.
  void _preset(String text) {
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: 0, extentOffset: text.length),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Registers a background save so "Done" can wait for it, and reports its
  /// failure - unless the flow has since restarted.
  void _track(Future<Object?> future, {VoidCallback? onError}) {
    final generation = _generation;
    _pending.add(future.then<void>((_) {}, onError: (Object e) {
      if (!mounted || generation != _generation) return;
      onError?.call();
      _toast(e is ApiException ? e.userMessage : ApiException.genericMessage);
    }));
  }

  /* --------------------------------- steps --------------------------------- */

  void _submit() {
    switch (_stage) {
      case _Stage.name:
        _commitName();
      case _Stage.dayTitle:
        _commitDay();
      case _Stage.mealName:
        _commitMeal();
      case _Stage.ingredients:
        final visible = _visible;
        if (_input.text.trim().isEmpty) {
          if (_ingredients.isNotEmpty) _saveMeal();
        } else if (visible.isNotEmpty) {
          _add(visible.first);
        }
      case _Stage.done:
        break;
    }
  }

  void _commitName() {
    final typed = _input.text.trim();
    final name = typed.isEmpty ? _presetName : typed;
    HapticFeedback.lightImpact();

    final plan = _plans.createOrUpdate(
      name: name,
      periodType: _kPeriodType,
      durationDays: _kDurationDays,
    );
    _dietId = plan;
    _track(plan, onError: () => _restart(name));

    setState(() {
      _titleFrom = _heroTop;
      _titleFromSize = _heroSize;
      _dietName = name;
      _stage = _Stage.dayTitle;
    });
    _preset(_presetDay(_day));
    _intro.forward(from: 0);
    _focus.requestFocus();
  }

  /// The diet itself failed to save - everything chained after it is dead,
  /// so go back to naming it (keeping what they typed).
  void _restart(String name) {
    setState(() {
      _generation++;
      _stage = _Stage.name;
      _day = 1;
      _dietName = null;
      _dayTitle = null;
      _mealTitle = null;
      _completedDays.clear();
      _dayMeals.clear();
      _previousDayMeals = const [];
      _resetMealState();
    });
    _preset(name);
    _intro.forward(from: 0);
    _focus.requestFocus();
  }

  String _typedDayTitle() {
    final typed = _input.text.trim();
    return typed.isEmpty ? _presetDay(_day) : typed;
  }

  Future<String?> _saveDay(String title) {
    final day = _day;
    final dayId = _dietId!.then((dietId) => _plans.saveDay(
          dietPlanId: dietId!,
          dayIndex: day,
          title: title,
        ));
    _track(dayId);
    return dayId;
  }

  void _commitDay() {
    final title = _typedDayTitle();
    HapticFeedback.lightImpact();
    _dayId = _saveDay(title);

    setState(() {
      _dayFrom = _heroTop;
      _dayFromSize = _heroSize;
      _dayTitle = title;
      _dayMeals.clear();
      _stage = _Stage.mealName;
    });
    _startMeal();
  }

  /// Copies the previous day's meals onto this one and moves on.
  void _repeatPreviousDay() {
    final title = _typedDayTitle();
    HapticFeedback.lightImpact();
    final dayId = _saveDay(title);
    final meals = _previousDayMeals;
    for (var i = 0; i < meals.length; i++) {
      _track(dayId.then((id) => _plans.createCustomMeal(
            dietPlanDayId: id!,
            mealType: meals[i].mealType,
            title: meals[i].title,
            sortOrder: i,
            items: meals[i].items,
          )));
    }
    _completedDays.add(_day);
    _advance();
  }

  void _startMeal() {
    _mealType = _nextMealType;
    _preset(_mealType);
    _intro.forward(from: 0);
    _focus.requestFocus();
  }

  void _pickMealType(String type) {
    if (type == _mealType) return;
    HapticFeedback.selectionClick();
    // Still on the suggested name - follow the slot they picked.
    final followsType = _input.text.trim().isEmpty ||
        kMealTypes.contains(_input.text.trim());
    setState(() => _mealType = type);
    if (followsType) _preset(type);
  }

  void _commitMeal() {
    final typed = _input.text.trim();
    final title = typed.isEmpty ? _mealType : typed;
    HapticFeedback.lightImpact();
    setState(() {
      _mealFrom = _mealInputTop;
      _mealFromSize = _heroSize;
      _mealTitle = title;
      _stage = _Stage.ingredients;
      _resetMealState();
    });
    _input.clear();
    _intro.forward(from: 0);
    _focus.requestFocus();
  }

  void _saveMeal() {
    if (_ingredients.isEmpty) return;
    HapticFeedback.lightImpact();
    final items = [
      for (final i in _ingredients)
        (foodNutritionId: i.food.foodNutritionId, grams: i.grams),
    ];
    final meal = _SavedMeal(
      title: _mealTitle ?? _mealType,
      mealType: _mealType,
      items: items,
      calories: _totals.calories.round(),
    );
    final sortOrder = _dayMeals.length;
    final save = _dayId!.then((dayId) => _plans.createCustomMeal(
          dietPlanDayId: dayId!,
          mealType: meal.mealType,
          title: meal.title,
          sortOrder: sortOrder,
          items: items,
        ));
    final day = _day;
    _track(save, onError: () {
      if (day == _day) setState(() => _dayMeals.remove(meal));
    });

    _focus.unfocus();
    setState(() {
      _dayMeals.add(meal);
      _mealTitle = null;
      _stage = _Stage.mealName;
      _resetMealState();
    });
    _startMeal();
  }

  void _nextDay() {
    HapticFeedback.lightImpact();
    _completedDays.add(_day);
    if (_dayMeals.isNotEmpty) _previousDayMeals = List.of(_dayMeals);
    _advance();
  }

  void _advance() {
    if (_day >= _kDurationDays) {
      _focus.unfocus();
      setState(() => _stage = _Stage.done);
      return;
    }
    setState(() {
      _day++;
      _dayTitle = null;
      _mealTitle = null;
      _dayMeals.clear();
      _stage = _Stage.dayTitle;
      _resetMealState();
    });
    _preset(_presetDay(_day));
    _intro.forward(from: 0);
    _focus.requestFocus();
  }

  void _resetMealState() {
    _debounce?.cancel();
    _queryToken++;
    _ingredients.clear();
    _chipKeys.clear();
    _rowKeys.clear();
    _results = const [];
    _searching = false;
  }

  Future<void> _done() async {
    setState(() => _finishing = true);
    await Future.wait(_pending);
    if (mounted) Navigator.of(context).pop();
  }

  /* ------------------------------ ingredients ------------------------------ */

  ({double calories, double protein, double carbs, double fats}) get _totals {
    var calories = 0.0, protein = 0.0, carbs = 0.0, fats = 0.0;
    for (final i in _ingredients) {
      calories += i.calories;
      protein += i.protein;
      carbs += i.carbs;
      fats += i.fats;
    }
    return (calories: calories, protein: protein, carbs: carbs, fats: fats);
  }

  List<FoodItem> get _visible {
    final taken = {for (final i in _ingredients) i.food.foodNutritionId};
    return _results.where((f) => !taken.contains(f.foodNutritionId)).toList();
  }

  void _onChanged(String value) {
    if (_stage != _Stage.ingredients) {
      // Keeps the save button's label in step with the typed name.
      if (_stage == _Stage.mealName) setState(() {});
      return;
    }
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _queryToken++;
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 220), () => _search(query));
  }

  Future<void> _search(String query) async {
    final token = ++_queryToken;
    try {
      final results = await _meals.searchFoods(query);
      if (!mounted || token != _queryToken) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || token != _queryToken) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
    }
  }

  Future<void> _add(FoodItem food) async {
    final id = food.foodNutritionId;
    if (_ingredients.any((i) => i.food.foodNutritionId == id)) return;
    final from = overlayRectOf(context, _rowKeys[id]);
    HapticFeedback.selectionClick();
    // Drop the keyboard so the layout eases back and the chip flies home.
    _focus.unfocus();

    final entry =
        _Ingredient(food, grams: food.defaultGrams, landed: from == null);
    setState(() => _ingredients.add(entry));
    if (_input.text.isNotEmpty) {
      _input.clear();
      _onChanged('');
    }
    if (from == null) return;

    // The chip is laid out (invisibly) this frame; fly into wherever it
    // landed, then reveal it.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final to = overlayRectOf(context, _chipKeys[id]);
    if (to == null) {
      setState(() => entry.landed = true);
      return;
    }
    late final OverlayEntry flight;
    flight = flyExercise(context,
        label: food.name,
        from: from,
        to: to,
        // The chip is still sliding back into place as the search folds away.
        track: () => overlayRectOf(context, _chipKeys[id]), onLanded: () {
      _flights.remove(flight);
      if (mounted) setState(() => entry.landed = true);
    });
    _flights.add(flight);
  }

  void _remove(_Ingredient entry) {
    HapticFeedback.selectionClick();
    setState(() => _ingredients.remove(entry));
  }

  Future<void> _editGrams(_Ingredient entry) async {
    final grams = await showDialog<double>(
      context: context,
      builder: (_) => _GramsDialog(
        foodName: entry.food.name,
        initialGrams: entry.grams,
      ),
    );
    if (!mounted || grams == null) return;
    if (grams <= 0) {
      _remove(entry);
    } else {
      setState(() => entry.grams = grams);
    }
  }

  /* --------------------------------- build --------------------------------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: AuthBlobBackground(layout: 3)),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            child: _stage == _Stage.done
                ? _buildSuccess(context)
                : KeyedSubtree(
                    key: const ValueKey('flow'),
                    child: _buildFlow(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlow() {
    return SafeArea(
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.marginMobile),
              child: LayoutBuilder(builder: (context, constraints) {
                final width = constraints.maxWidth;
                final titleLines = _dietName == null
                    ? 1
                    : _lineCount(_dietName!, AppTypography.headlineLg, width);
                final dayLines = _dayTitle == null
                    ? 1
                    : _lineCount(_dayTitle!, AppTypography.headlineMd, width);
                final mealLines = _mealTitle == null
                    ? 1
                    : _lineCount(_mealTitle!, AppTypography.headlineSm, width);
                final dayEyebrowTop = titleLines * _kTitleLine + AppSpacing.lg;
                final dayTop = dayEyebrowTop + _kEyebrowLine + AppSpacing.xs;
                final dayBottom = dayTop + dayLines * _kDayLine;
                final mealEyebrowTop = dayBottom + AppSpacing.lg;
                final mealTop = mealEyebrowTop + _kEyebrowLine + AppSpacing.xs;
                final ingredientTop =
                    mealTop + mealLines * _kMealLine + AppSpacing.xl;
                _mealInputTop = dayBottom + AppSpacing.xl;
                _heroTop = (constraints.maxHeight * 0.26)
                    .clamp(titleLines * _kTitleLine + AppSpacing.xxxl, 200.0);
                final inputTop = _searchTakeover
                    ? 0.0
                    : switch (_stage) {
                        _Stage.ingredients => ingredientTop,
                        _Stage.mealName => _mealInputTop,
                        _ => _heroTop,
                      };
                // Tapping anywhere empty drops the keyboard (and drains the
                // underline); tapping the field brings both back.
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _focus.unfocus,
                  child: Stack(
                    children: [
                      Positioned.fill(
                          child: _buildInputColumn(inputTop, width)),
                      Positioned.fill(
                        child: IgnorePointer(
                          // Faded rather than removed, so the titles' morphs
                          // aren't replayed when the search hands the room
                          // back.
                          child: AnimatedOpacity(
                            opacity: _searchTakeover ? 0 : 1,
                            duration: kInkQuick,
                            curve: Curves.easeOutCubic,
                            child: _buildHeaders(
                              dayEyebrowTop: dayEyebrowTop,
                              dayTop: dayTop,
                              mealEyebrowTop: mealEyebrowTop,
                              mealTop: mealTop,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xxs,
          AppSpacing.marginMobile, AppSpacing.md),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _DayProgress(
              completed: _completedDays,
              current: _stage == _Stage.name ? null : _day,
            ),
          ),
        ],
      ),
    );
  }

  int _lineCount(String text, TextStyle style, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: _kMaxTitleLines,
    )..layout(maxWidth: width);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines.clamp(1, _kMaxTitleLines);
  }

  /// A heading that takes over from the typed text on the exact same frame
  /// (zero-length in); only the outgoing one fades.
  Widget _headingSwitcher(Widget child) {
    return AnimatedSwitcher(
      duration: Duration.zero,
      reverseDuration: kInkQuick,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -0.04),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }

  Widget _eyebrow(String text, double top) {
    return Positioned(
      top: top,
      left: 0,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: kInkMorph,
        curve: Curves.easeOut,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child:
              Transform.translate(offset: Offset(0, 6 * (1 - t)), child: child),
        ),
        child: Text(
          text,
          style: AppTypography.labelCaps.copyWith(color: AppColors.accent),
        ),
      ),
    );
  }

  Widget _buildHeaders({
    required double dayEyebrowTop,
    required double dayTop,
    required double mealEyebrowTop,
    required double mealTop,
  }) {
    final showDay = (_stage == _Stage.mealName ||
            _stage == _Stage.ingredients) &&
        _dayTitle != null;
    final showMeal = _stage == _Stage.ingredients && _mealTitle != null;
    return Stack(
      children: [
        if (_dietName != null)
          Positioned.fill(
            child: InkMorphText(
              key: ValueKey('title-$_generation'),
              text: _dietName!,
              fromTop: _titleFrom,
              toTop: 0,
              fromStyle: heroStyle(_titleFromSize),
              toStyle: AppTypography.headlineLg,
            ),
          ),
        Positioned.fill(
          child: _headingSwitcher(
            showDay
                ? Stack(
                    key: ValueKey('day-$_day-$_generation'),
                    children: [
                      _eyebrow('DAY $_day OF $_kDurationDays', dayEyebrowTop),
                      Positioned.fill(
                        child: InkMorphText(
                          text: _dayTitle!,
                          fromTop: _dayFrom,
                          toTop: dayTop,
                          fromStyle: heroStyle(_dayFromSize),
                          toStyle: AppTypography.headlineMd,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('no-day')),
          ),
        ),
        Positioned.fill(
          child: _headingSwitcher(
            showMeal
                ? Stack(
                    key: ValueKey(
                        'meal-$_day-${_dayMeals.length}-$_generation'),
                    children: [
                      _eyebrow(_mealType.toUpperCase(), mealEyebrowTop),
                      Positioned.fill(
                        child: InkMorphText(
                          text: _mealTitle!,
                          fromTop: _mealFrom,
                          toTop: mealTop,
                          fromStyle: heroStyle(_mealFromSize),
                          toStyle: AppTypography.headlineSm,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('no-meal')),
          ),
        ),
      ],
    );
  }

  /// The one text field, and what hangs off it. Its position in this tree
  /// never changes, so it keeps focus (and the keyboard) across every step.
  Widget _buildInputColumn(double inputTop, double width) {
    final intro = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    final picking = _stage == _Stage.ingredients;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: kInkMorph,
          curve: Curves.easeOutCubic,
          height: inputTop,
        ),
        AnimatedSize(
          duration: kInkQuick,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: picking && _ingredients.isNotEmpty && !_searchTakeover
              ? Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 136),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final entry in _ingredients)
                            ExerciseChip(
                              key: _chipKeys.putIfAbsent(
                                  entry.food.foodNutritionId, GlobalKey.new),
                              label: entry.food.name,
                              detail: '${_formatGrams(entry.grams)} g',
                              visible: entry.landed,
                              // Tapping the chip sets its amount.
                              onTap: () => _editGrams(entry),
                              onRemove: () => _remove(entry),
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        FadeTransition(
          opacity: intro,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.35), end: Offset.zero)
                .animate(intro),
            child: _buildField(width),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Outside the intro fade: focus doesn't change between steps, so
        // the line stays put while the text swaps above it.
        FocusUnderline(animation: _underline),
        Expanded(
          child: switch (_stage) {
            _Stage.ingredients => _buildResults(),
            _Stage.mealName => _buildMealSlot(),
            _ => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }

  Widget _buildField(double width) {
    final picking = _stage == _Stage.ingredients;
    final hint = switch (_stage) {
      _Stage.name => _presetName,
      _Stage.dayTitle => _presetDay(_day),
      _Stage.mealName => _mealType,
      _ => 'Search foods',
    };
    if (picking) return _textField(AppTypography.headlineSm, hint, picking);
    // Re-fit on every keystroke. Applied directly rather than tweened - an
    // in-between size is larger than the fit and would wrap for a frame.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _input,
      builder: (context, value, _) {
        final size =
            fitHeroSize(context, value.text.isEmpty ? hint : value.text, width);
        _heroSize = size;
        return _textField(heroStyle(size), hint, picking);
      },
    );
  }

  Widget _textField(TextStyle style, String hint, bool picking) {
    return TextField(
      controller: _input,
      focusNode: _focus,
      autofocus: true,
      // Titles wrap (once they're down at min size); search stays one line.
      // An explicit text keyboard keeps the action key submitting.
      minLines: 1,
      maxLines: picking ? 1 : null,
      keyboardType: TextInputType.text,
      style: style,
      cursorColor: AppColors.accent,
      textCapitalization:
          picking ? TextCapitalization.none : TextCapitalization.words,
      textInputAction: picking ? TextInputAction.done : TextInputAction.next,
      decoration: inkDecoration(hint, style),
      onChanged: _onChanged,
      onSubmitted: (_) => _submit(),
      // Swallow the default unfocus so the keyboard stays up between steps.
      onEditingComplete: () {},
    );
  }

  /// Under the meal's name: which slot it fills, then the meals already on
  /// this day.
  Widget _buildMealSlot() {
    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.md),
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final type in kMealTypes)
              _SlotPill(
                label: type,
                selected: type == _mealType,
                onTap: () => _pickMealType(type),
              ),
          ],
        ),
        if (_dayMeals.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text('ON THIS DAY', style: AppTypography.labelCaps),
          const SizedBox(height: AppSpacing.xs),
          for (final meal in _dayMeals)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _SavedMealRow(meal: meal),
            ),
        ],
      ],
    );
  }

  Widget _buildResults() {
    final items = _visible;
    final query = _input.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xs),
        // Only built while searching - an indeterminate bar keeps ticking
        // even when faded out.
        SizedBox(
          height: 2,
          child: _searching
              ? LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.accent,
                  backgroundColor: Colors.transparent,
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (query.isEmpty && !_searchTakeover) _buildTotals(),
        Expanded(
          child: items.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: AnimatedOpacity(
                    opacity: query.isNotEmpty && !_searching ? 1 : 0,
                    duration: kInkQuick,
                    child: Text(
                      'No matches for "$query"',
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final food = items[i];
                    return _FoodResultRow(
                      key: _rowKeys.putIfAbsent(
                          food.foodNutritionId, GlobalKey.new),
                      food: food,
                      onTap: () => _add(food),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// The meal's running macros - or, before the first ingredient, a nudge.
  Widget _buildTotals() {
    final muted =
        AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant);
    if (_ingredients.isEmpty) {
      return Text('Search for an ingredient to add it to this meal.',
          style: muted);
    }
    final t = _totals;
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: '${t.calories.round()} kcal',
          style: AppTypography.bodySm.copyWith(
              color: AppColors.highEmphasis, fontWeight: FontWeight.w600),
        ),
        TextSpan(
          text: '  ·  ${t.protein.round()}g protein  ·  '
              '${t.carbs.round()}g carbs  ·  ${t.fats.round()}g fat',
        ),
      ]),
      style: muted,
    );
  }

  Widget _buildBottomBar() {
    final lastDay = _day >= _kDurationDays;
    final Widget bar = switch (_stage) {
      _Stage.name => PrimaryPillButton(
          key: const ValueKey('bar-name'),
          label: 'Continue',
          icon: Icons.arrow_forward_rounded,
          onPressed: _commitName,
        ),
      _Stage.dayTitle => _previousDayMeals.isEmpty
          ? PrimaryPillButton(
              key: ValueKey('bar-day-$_day'),
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              onPressed: _commitDay,
            )
          : Row(
              key: ValueKey('bar-day-repeat-$_day'),
              children: [
                Expanded(
                  child: SecondaryPillButton(
                    label: 'Repeat day ${_day - 1}',
                    icon: Icons.repeat_rounded,
                    onPressed: _repeatPreviousDay,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryPillButton(
                    label: 'Continue',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: _commitDay,
                  ),
                ),
              ],
            ),
      _Stage.mealName => _dayMeals.isEmpty
          ? PrimaryPillButton(
              key: ValueKey('bar-meal-$_day'),
              label: 'Add ingredients',
              icon: Icons.arrow_forward_rounded,
              onPressed: _commitMeal,
            )
          : Row(
              key: ValueKey('bar-meal-next-$_day'),
              children: [
                Expanded(
                  child: SecondaryPillButton(
                    label: lastDay ? 'Finish' : 'Next day',
                    icon: lastDay
                        ? Icons.check_rounded
                        : Icons.arrow_forward_rounded,
                    onPressed: _nextDay,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryPillButton(
                    label: 'Add meal',
                    icon: Icons.add_rounded,
                    onPressed: _commitMeal,
                  ),
                ),
              ],
            ),
      _ => PrimaryPillButton(
          key: ValueKey('bar-ingredients-$_day'),
          label: 'Save meal',
          icon: Icons.check_rounded,
          onPressed: _ingredients.isEmpty ? null : _saveMeal,
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile, AppSpacing.xs,
          AppSpacing.marginMobile, AppSpacing.md),
      child: AnimatedSwitcher(
        duration: kInkQuick,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        child: bar,
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Stack(
      key: const ValueKey('success'),
      fit: StackFit.expand,
      children: [
        SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 56, color: AppColors.accent),
                const SizedBox(height: AppSpacing.lg),
                Text('${_dietName ?? 'Your diet'} is ready',
                    style: AppTypography.headlineLg,
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Every day is planned out and ready to go.',
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryPillButton(
                  label: 'Done',
                  icon: Icons.check_rounded,
                  isLoading: _finishing,
                  onPressed: _done,
                ),
              ],
            ),
          ),
        ),
        IgnorePointer(
          child: Lottie.asset(
            'assets/lottie_animations/confetti.json',
            fit: BoxFit.cover,
            repeat: false,
          ),
        ),
      ],
    );
  }
}

String _formatGrams(double grams) => grams == grams.roundToDouble()
    ? grams.toStringAsFixed(0)
    : grams.toStringAsFixed(1);

/// Seven segments - filled for finished days, tinted for the day being
/// built.
class _DayProgress extends StatelessWidget {
  final Set<int> completed;
  final int? current;

  const _DayProgress({required this.completed, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var day = 1; day <= _kDurationDays; day++)
          Expanded(
            child: AnimatedContainer(
              duration: kInkMorph,
              curve: Curves.easeOutCubic,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.full),
                color: completed.contains(day)
                    ? AppColors.accent
                    : day == current
                        ? AppColors.accent.withValues(alpha: 0.25)
                        : AppColors.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
    );
  }
}

/// Breakfast / Lunch / Dinner / Snack choice under the meal's name.
class _SlotPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SlotPill(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: kInkQuick,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          label,
          style: AppTypography.bodySm.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.onAccent : AppColors.highEmphasis,
          ),
        ),
      ),
    );
  }
}

class _SavedMealRow extends StatelessWidget {
  final _SavedMeal meal;

  const _SavedMealRow({required this.meal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.mealType.toUpperCase(),
                    style: AppTypography.labelCaps
                        .copyWith(color: AppColors.accent)),
                Text(meal.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.highEmphasis)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${meal.calories} kcal · ${meal.items.length} '
            '${meal.items.length == 1 ? 'ingredient' : 'ingredients'}',
            style:
                AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// A tappable food search result - the start of an ingredient's flight.
class _FoodResultRow extends StatelessWidget {
  final FoodItem food;
  final VoidCallback onTap;

  const _FoodResultRow({super.key, required this.food, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final detail = [
      if (food.brandName != null && food.brandName!.isNotEmpty) food.brandName!,
      '${food.caloriesKcal.round()} kcal / 100 g',
    ].join(' · ');
    return Material(
      color: AppColors.surfaceContainer.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // Keeps focus (and the keyboard) on the search field.
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(food.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMd
                            .copyWith(color: AppColors.highEmphasis)),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.add_rounded, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sets how many grams of an ingredient go into the meal. Returns the new
/// amount (0 to remove it), or null when dismissed.
class _GramsDialog extends StatefulWidget {
  final String foodName;
  final double initialGrams;

  const _GramsDialog({required this.foodName, required this.initialGrams});

  @override
  State<_GramsDialog> createState() => _GramsDialogState();
}

class _GramsDialogState extends State<_GramsDialog> {
  late final TextEditingController _grams = TextEditingController(
    text: _formatGrams(widget.initialGrams),
  )..selection = TextSelection(
      baseOffset: 0, extentOffset: _formatGrams(widget.initialGrams).length);

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  void _save() {
    final grams = double.tryParse(_grams.text.trim().replaceAll(',', '.'));
    if (grams == null || grams < 0) return;
    Navigator.of(context).pop(grams.clamp(0, 5000).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.foodName, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: TextField(
        controller: _grams,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: const InputDecoration(labelText: 'Amount', suffixText: 'g'),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(0.0),
          child: const Text('Remove'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

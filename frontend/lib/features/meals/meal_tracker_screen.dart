import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/silen_button.dart';
import '../auth/widgets/auth_blob_background.dart';
import '../splits/widgets/ink_field.dart';
import 'meal_controller.dart';
import 'meal_models.dart';
import 'widgets/food_picker_sheet.dart';

// Line heights of the committed meal name (headlineLg) and the totals strip
// that settles beneath it. The name may wrap to two lines, so everything
// under it is placed from a measured line count.
const double _kTitleLine = 34;
const double _kTotalsHeight = 58;
const int _kMaxTitleLines = 2;

const _kIntro = Duration(milliseconds: 260);
const _kSearchDebounce = Duration(milliseconds: 220);
const _kMinQueryLength = 2;

// Corner radius shared by result rows and ingredient cards, so a food's
// flight between them never changes shape.
const double _kRowRadius = 14;

enum _Stage { name, foods }

/// Builds a meal the way the split wizard builds a split - one text field
/// (bottom rule only) that keeps focus, so the keyboard never drops:
///
/// 1. the meal's name, as big type ("Lunch" preset from the time of day) -
///    committing it lifts the text up into the screen's title;
/// 2. the ingredients - the field shrinks to a search line over the food
///    database, and tapping a result flies it into the ingredient list, where
///    its grams can be stepped and its macros are tracked live. The meal's
///    combined totals sit under the title.
///
/// With [existing] it opens straight on step 2 to edit that meal. Pops
/// `true` once the meal has been saved or deleted.
class MealTrackerScreen extends StatefulWidget {
  final MealController controller;

  /// The logged meal being edited, or null to log a new one.
  final MealLog? existing;

  const MealTrackerScreen({super.key, required this.controller, this.existing});

  @override
  State<MealTrackerScreen> createState() => _MealTrackerScreenState();
}

class _Ingredient {
  /// Local identity - the same food may come back from the server without a
  /// catalog id, so neither the id nor the name is a safe key.
  final int key;
  MealLogItem item;
  bool landed;

  _Ingredient(this.key, this.item, {required this.landed});
}

class _MealTrackerScreenState extends State<MealTrackerScreen>
    with TickerProviderStateMixin {
  MealController get _controller => widget.controller;

  final _input = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _intro;

  /// Fills the field's bottom line in on focus and drains it on blur.
  late final AnimationController _underline;

  late _Stage _stage;
  late String _mealType;
  String? _mealName;

  /// Where the big input sits for the current layout (it follows the
  /// keyboard), captured into [_titleFrom] at commit time so the morphing
  /// name starts exactly where the typed text was.
  double _heroTop = 120;
  double _titleFrom = 120;
  double _heroSize = kHeroMaxSize;
  double _titleFromSize = kHeroMaxSize;

  /// Bumped each time the name is (re)committed, restarting the morph.
  int _generation = 0;

  final _ingredients = <_Ingredient>[];
  int _nextKey = 0;
  final _ingredientKeys = <int, GlobalKey>{};
  final _rowKeys = <int, GlobalKey>{};

  List<FoodItem> _results = const [];
  String _resultsQuery = '';
  bool _searching = false;
  bool _searchFailed = false;
  Timer? _debounce;
  int _queryToken = 0;

  final _flights = <OverlayEntry>[];
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  static String _mealTypeForNow() {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Breakfast';
    if (hour < 15) return 'Lunch';
    if (hour >= 17 && hour < 22) return 'Dinner';
    return 'Snack';
  }

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: _kIntro)..forward();
    _underline = AnimationController(vsync: this, duration: kInkMorph);
    _focus.addListener(_onFocusChanged);

    final existing = widget.existing;
    if (existing == null) {
      _stage = _Stage.name;
      _mealType = _mealTypeForNow();
      _preset(_mealType);
    } else {
      // Already named: the title starts settled instead of morphing in.
      _stage = _Stage.foods;
      _mealType = existing.mealType;
      _mealName = existing.title;
      _titleFrom = 0;
      _titleFromSize = AppTypography.headlineLg.fontSize ?? 30;
      for (final item in existing.items) {
        _ingredients.add(_Ingredient(_nextKey++, item, landed: true));
      }
    }
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
  }

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

  List<MealLogItem> get _items => [for (final i in _ingredients) i.item];

  bool get _hasChanges {
    final existing = widget.existing;
    if (existing == null) return _ingredients.isNotEmpty;
    return _mealName != existing.title ||
        _mealType != existing.mealType ||
        !listEquals(_items, existing.items);
  }

  /* --------------------------------- steps --------------------------------- */

  void _submit() {
    switch (_stage) {
      case _Stage.name:
        _commitName();
      case _Stage.foods:
        final results = _visibleResults;
        if (results.isNotEmpty) _add(results.first);
    }
  }

  void _commitName() {
    final typed = _input.text.trim();
    final name = typed.isEmpty ? _mealType : typed;
    HapticFeedback.lightImpact();

    setState(() {
      _titleFrom = _heroTop;
      _titleFromSize = _heroSize;
      _mealName = name;
      _mealType = _typeFromName(name) ?? _mealType;
      _stage = _Stage.foods;
      _generation++;
    });
    _input.clear();
    _intro.forward(from: 0);
    _focus.requestFocus();
  }

  /// "Late lunch" is a Lunch - the name picks the type when it names one.
  static String? _typeFromName(String name) {
    final lower = name.toLowerCase();
    for (final type in kMealTypes) {
      if (lower.contains(type.toLowerCase())) return type;
    }
    return null;
  }

  /// Tapping the title drops it back into the big field to rename; the
  /// ingredients wait, hidden, until it's committed again.
  void _renameMeal() {
    if (_stage != _Stage.foods || _saving) return;
    HapticFeedback.selectionClick();
    _debounce?.cancel();
    _queryToken++;
    setState(() {
      _stage = _Stage.name;
      _results = const [];
      _searching = false;
      _searchFailed = false;
    });
    _preset(_mealName ?? _mealType);
    _intro.forward(from: 0);
    _focus.requestFocus();
  }

  void _cycleMealType() {
    HapticFeedback.selectionClick();
    final index = kMealTypes.indexOf(_mealType);
    setState(() => _mealType = kMealTypes[(index + 1) % kMealTypes.length]);
  }

  Future<void> _save() async {
    if (_ingredients.isEmpty || _saving) return;
    setState(() => _saving = true);
    final ok = await _controller.saveTrackedMeal(
      existing: widget.existing,
      mealType: _mealType,
      title: _mealName ?? _mealType,
      items: _items,
    );
    if (!mounted) return;
    if (ok) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _saving = false);
    final error = _controller.actionError;
    if (error != null) _toast(error);
  }

  Future<void> _delete() async {
    final confirmed = await _ask(
      title: 'Delete this meal?',
      message: 'It will be removed from this day\'s totals.',
      stay: 'Keep it',
      leave: 'Delete',
    );
    if (confirmed != true || !mounted) return;
    await _controller.deleteMeal(widget.existing!.mealLogId);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _confirmExit() async {
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await _ask(
      title: 'Discard this meal?',
      message: _isEditing
          ? 'Your changes to this meal won\'t be saved.'
          : 'The foods you\'ve added won\'t be logged.',
      stay: 'Keep editing',
      leave: 'Discard',
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  Future<bool?> _ask({
    required String title,
    required String message,
    required String stay,
    required String leave,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Text(title, style: AppTypography.headlineSm),
        content: Text(message,
            style: AppTypography.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(stay, style: AppTypography.bodyMd)),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(leave,
                  style:
                      AppTypography.bodyMd.copyWith(color: AppColors.error))),
        ],
      ),
    );
  }

  /* -------------------------------- search -------------------------------- */

  List<FoodItem> get _visibleResults {
    final taken = {
      for (final i in _ingredients)
        if (i.item.foodNutritionId != null) i.item.foodNutritionId,
    };
    return _results.where((f) => !taken.contains(f.foodNutritionId)).toList();
  }

  void _onChanged(String value) {
    if (_stage != _Stage.foods) return;
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < _kMinQueryLength) {
      _queryToken++;
      setState(() {
        _results = const [];
        _resultsQuery = '';
        _searching = false;
        _searchFailed = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(_kSearchDebounce, () => _search(query));
  }

  Future<void> _search(String query) async {
    final token = ++_queryToken;
    try {
      final results = await _controller.searchFoods(query);
      if (!mounted || token != _queryToken) return;
      setState(() {
        _results = results;
        _resultsQuery = query;
        _searching = false;
        _searchFailed = false;
      });
    } catch (_) {
      if (!mounted || token != _queryToken) return;
      setState(() {
        _results = const [];
        _resultsQuery = query;
        _searching = false;
        _searchFailed = true;
      });
    }
  }

  void _clearSearch() {
    if (_input.text.isEmpty) return;
    _input.clear();
    _onChanged('');
  }

  /* ------------------------------ ingredients ------------------------------ */

  Future<void> _add(FoodItem food) async {
    final from = overlayRectOf(context, _rowKeys[food.foodNutritionId]);
    HapticFeedback.selectionClick();

    final entry = _Ingredient(
      _nextKey++,
      MealLogItem.fromFood(food, food.defaultGrams),
      landed: from == null,
    );
    setState(() => _ingredients.add(entry));
    _clearSearch();
    if (from == null) return;

    // The card is laid out (invisibly) this frame; fly into wherever it
    // landed, then reveal it.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final to = overlayRectOf(context, _ingredientKeys[entry.key]);
    if (to == null) {
      setState(() => entry.landed = true);
      return;
    }
    late final OverlayEntry flight;
    flight = flyExercise(
      context,
      label: food.name,
      from: from,
      to: to,
      toRadius: _kRowRadius,
      onLanded: () {
        _flights.remove(flight);
        if (mounted) setState(() => entry.landed = true);
      },
    );
    _flights.add(flight);
  }

  /// Not in the database - add it from the label, then straight into the
  /// meal.
  Future<void> _addCustom() async {
    final food = await showCustomFoodSheet(context,
        controller: _controller, initialName: _input.text.trim());
    if (food == null || !mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _ingredients.add(_Ingredient(
        _nextKey++, MealLogItem.fromFood(food, food.defaultGrams),
        landed: true)));
    _clearSearch();
    _focus.requestFocus();
  }

  void _remove(_Ingredient entry) {
    HapticFeedback.selectionClick();
    setState(() {
      _ingredients.remove(entry);
      _ingredientKeys.remove(entry.key);
    });
  }

  void _setGrams(_Ingredient entry, double grams) {
    final clamped = grams.clamp(1, 5000).toDouble();
    if (clamped == entry.item.grams) return;
    HapticFeedback.selectionClick();
    setState(() => entry.item = entry.item.withGrams(clamped));
  }

  /// Small foods move in 5 g steps, everything else in 10 g, always landing
  /// on a round number.
  void _step(_Ingredient entry, int direction) {
    final grams = entry.item.grams;
    final step = (direction < 0 ? grams <= 50 : grams < 50) ? 5.0 : 10.0;
    final next = direction > 0
        ? (grams / step).floor() * step + step
        : (grams / step).ceil() * step - step;
    _setGrams(entry, next < step ? step : next);
  }

  Future<void> _editGrams(_Ingredient entry) async {
    final grams = await showGramsSheet(context,
        title: entry.item.name,
        initialGrams: entry.item.grams,
        food: entry.item.food);
    if (grams == null || !mounted) return;
    _setGrams(entry, grams);
  }

  /* --------------------------------- build --------------------------------- */

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: AuthBlobBackground(layout: 3)),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.marginMobile),
                      child: LayoutBuilder(builder: _buildBody),
                    ),
                  ),
                  _buildBottomBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final titleLines = _mealName == null
        ? 1
        : _lineCount(_mealName!, AppTypography.headlineLg, width);
    final totalsTop = titleLines * _kTitleLine + AppSpacing.sm;
    final foodsTop = totalsTop + _kTotalsHeight + AppSpacing.md;
    _heroTop = (constraints.maxHeight * 0.26)
        .clamp(titleLines * _kTitleLine + AppSpacing.xxxl, 200.0);
    final inputTop = _stage == _Stage.foods ? foodsTop : _heroTop;
    // Ingredients get up to about a third of the room; beyond that they
    // scroll, newest kept in view.
    final listMax = (constraints.maxHeight * 0.34).clamp(76.0, 260.0);

    // Tapping anywhere empty drops the keyboard (and drains the underline);
    // tapping the field brings both back.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.unfocus,
      child: Stack(
        children: [
          Positioned.fill(child: _buildInputColumn(inputTop, width, listMax)),
          Positioned.fill(child: _buildHeaders(totalsTop)),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xxs,
          AppSpacing.xs, AppSpacing.md),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _confirmExit,
          ),
          const Spacer(),
          _MealTypePill(type: _mealType, onTap: _cycleMealType),
          if (_isEditing)
            IconButton(
              tooltip: 'Delete meal',
              icon: Icon(Icons.delete_outline_rounded,
                  color: AppColors.onSurfaceVariant),
              onPressed: _delete,
            )
          else
            const SizedBox(width: AppSpacing.sm),
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

  /// The committed name as the title, and the meal's running totals under
  /// it. Drawn above the input column; only the title itself takes taps.
  Widget _buildHeaders(double totalsTop) {
    final showFoods = _stage == _Stage.foods && _mealName != null;
    return Stack(
      children: [
        if (showFoods)
          Positioned.fill(
            child: GestureDetector(
              onTap: _renameMeal,
              child: InkMorphText(
                key: ValueKey('title-$_generation'),
                text: _mealName!,
                fromTop: _titleFrom,
                toTop: 0,
                fromStyle: _titleFrom == 0
                    ? AppTypography.headlineLg
                    : heroStyle(_titleFromSize),
                toStyle: AppTypography.headlineLg,
                maxLines: _kMaxTitleLines,
              ),
            ),
          ),
        if (showFoods)
          Positioned(
            key: ValueKey('totals-$_generation'),
            top: totalsTop,
            left: 0,
            right: 0,
            height: _kTotalsHeight,
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: kInkMorph,
                curve: Curves.easeOut,
                builder: (_, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                      offset: Offset(0, 8 * (1 - t)), child: child),
                ),
                child: _MealTotalsStrip(totals: MealTotals.of(_items)),
              ),
            ),
          ),
      ],
    );
  }

  /// The one text field, and what hangs off it. Its position in this tree
  /// never changes, so it keeps focus (and the keyboard) across both steps.
  Widget _buildInputColumn(double inputTop, double width, double listMax) {
    final intro = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    final picking = _stage == _Stage.foods;
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
          child: picking && _ingredients.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: listMax),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final entry in _ingredients)
                            Padding(
                              key: ValueKey(entry.key),
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.xs),
                              child: _IngredientCard(
                                key: _ingredientKeys.putIfAbsent(
                                    entry.key, GlobalKey.new),
                                id: entry.key,
                                item: entry.item,
                                visible: entry.landed,
                                onMinus: () => _step(entry, -1),
                                onPlus: () => _step(entry, 1),
                                onEditGrams: () => _editGrams(entry),
                                onRemove: () => _remove(entry),
                              ),
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
        Expanded(child: picking ? _buildResults() : const SizedBox.shrink()),
      ],
    );
  }

  Widget _buildField(double width) {
    final picking = _stage == _Stage.foods;
    final hint = picking
        ? (_ingredients.isEmpty ? 'Search ingredients' : 'Add another')
        : _mealType;
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
      autofocus: !_isEditing,
      // The name wraps (once it's down at min size); search stays one line.
      // An explicit text keyboard keeps the action key submitting.
      minLines: 1,
      maxLines: picking ? 1 : null,
      keyboardType: TextInputType.text,
      style: style,
      cursorColor: AppColors.accent,
      textCapitalization:
          picking ? TextCapitalization.none : TextCapitalization.words,
      textInputAction: picking ? TextInputAction.search : TextInputAction.next,
      decoration: inkDecoration(hint, style),
      onChanged: _onChanged,
      onSubmitted: (_) => _submit(),
      // Swallow the default unfocus so the keyboard stays up between steps.
      onEditingComplete: () {},
    );
  }

  Widget _buildResults() {
    final items = _visibleResults;
    final query = _input.text.trim();
    final settled = !_searching && query == _resultsQuery;
    final String? message;
    if (query.length < _kMinQueryLength) {
      message = _ingredients.isEmpty
          ? 'Search by name or barcode - "chicken breast", "oats"'
          : null;
    } else if (settled && _searchFailed) {
      message = 'Couldn\'t search right now. Try again in a moment.';
    } else if (settled && items.isEmpty) {
      message = 'No matches for "$query"';
    } else {
      message = null;
    }
    final canAddOwn = query.length >= _kMinQueryLength && settled;

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
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            children: [
              AnimatedSwitcher(
                duration: kInkQuick,
                child: message == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        key: ValueKey(message),
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          message,
                          style: AppTypography.bodySm
                              .copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      ),
              ),
              for (final food in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _FoodResultRow(
                    key: _rowKeys.putIfAbsent(
                        food.foodNutritionId, GlobalKey.new),
                    food: food,
                    onTap: () => _add(food),
                  ),
                ),
              AnimatedOpacity(
                opacity: canAddOwn ? 1 : 0,
                duration: kInkQuick,
                child: IgnorePointer(
                  ignoring: !canAddOwn,
                  child: _AddOwnFoodRow(
                    query: query,
                    emphasized: items.isEmpty,
                    onTap: _addCustom,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final kcal = MealTotals.of(_items).caloriesKcal;
    final Widget bar = switch (_stage) {
      _Stage.name => PrimaryPillButton(
          key: const ValueKey('bar-name'),
          label: 'Continue',
          icon: Icons.arrow_forward_rounded,
          onPressed: _commitName,
        ),
      _Stage.foods => PrimaryPillButton(
          key: const ValueKey('bar-foods'),
          label: _ingredients.isEmpty
              ? 'Add an ingredient'
              : 'Save meal · ${kcal.round()} kcal',
          icon: Icons.check_rounded,
          isLoading: _saving,
          onPressed: _ingredients.isEmpty ? null : _save,
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
}

/* ------------------------------------------------------------------------ */

String _fmt(double v) =>
    v >= 100 || v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

Color get _proteinColor => AppColors.accent;
Color get _carbsColor => AppColors.tertiaryContainer;
Color get _fatColor => AppColors.secondary;

/// The meal type, top right - a tap steps to the next one, so it can be
/// fixed without leaving the keyboard.
class _MealTypePill extends StatelessWidget {
  final String type;
  final VoidCallback onTap;

  const _MealTypePill({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerHigh.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: kInkQuick,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0, 0.4), end: Offset.zero)
                        .animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  type.toUpperCase(),
                  key: ValueKey(type),
                  style: AppTypography.labelCaps
                      .copyWith(color: AppColors.accent),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.unfold_more_rounded,
                  size: 16, color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// A number that counts to its new value instead of jumping.
class _RollingNumber extends StatelessWidget {
  final double value;
  final TextStyle style;
  final String suffix;

  const _RollingNumber(this.value, {required this.style, this.suffix = ''});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: kInkMorph,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text('${v.round()}$suffix', style: style),
    );
  }
}

/// The meal's combined calories and macros, under its title: calories large,
/// then protein / carbs / fat each with a bar showing its share of the
/// meal's energy.
class _MealTotalsStrip extends StatelessWidget {
  final MealTotals totals;

  const _MealTotalsStrip({required this.totals});

  @override
  Widget build(BuildContext context) {
    final p = totals.proteinG * 4;
    final c = totals.carbsG * 4;
    final f = totals.fatsG * 9;
    final energy = p + c + f;
    double share(double v) => energy <= 0 ? 0 : v / energy;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RollingNumber(totals.caloriesKcal,
                style: AppTypography.headlineMd
                    .copyWith(color: AppColors.highEmphasis)),
            Text('KCAL · ${totals.grams.round()} G',
                style: AppTypography.labelCaps),
          ],
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: _TotalsMacro(
              label: 'Protein',
              grams: totals.proteinG,
              share: share(p),
              color: _proteinColor),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _TotalsMacro(
              label: 'Carbs',
              grams: totals.carbsG,
              share: share(c),
              color: _carbsColor),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _TotalsMacro(
              label: 'Fat',
              grams: totals.fatsG,
              share: share(f),
              color: _fatColor),
        ),
      ],
    );
  }
}

class _TotalsMacro extends StatelessWidget {
  final String label;
  final double grams;
  final double share;
  final Color color;

  const _TotalsMacro({
    required this.label,
    required this.grams,
    required this.share,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RollingNumber(grams,
            suffix: 'g',
            style: AppTypography.bodyMd.copyWith(
                color: AppColors.highEmphasis, fontWeight: FontWeight.w600)),
        Text(label.toUpperCase(), style: AppTypography.labelCaps),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: SizedBox(
            height: 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: color.withValues(alpha: 0.18)),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: share),
                  duration: kInkMorph,
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: v.clamp(0, 1),
                    child: ColoredBox(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A catalog food in the search results, per 100 g - where a flight starts.
class _FoodResultRow extends StatelessWidget {
  final FoodItem food;
  final VoidCallback onTap;

  const _FoodResultRow({super.key, required this.food, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (food.isCustom)
        'Your food'
      else if (food.brandName != null && food.brandName!.isNotEmpty)
        food.brandName!,
      '${_fmt(food.caloriesKcal)} kcal / 100 g',
    ].join(' · ');
    return Material(
      color: AppColors.surfaceContainer.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(_kRowRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kRowRadius),
        // Keeps focus (and the keyboard) on the search field.
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSm
                            .copyWith(color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    MacroLine(
                      proteinG: food.proteinG,
                      carbsG: food.carbohydrateG,
                      fatsG: food.fatG,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.add_rounded, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Add "query" as a new food" - the way out when the database is missing
/// it. Stronger when nothing matched.
class _AddOwnFoodRow extends StatelessWidget {
  final String query;
  final bool emphasized;
  final VoidCallback onTap;

  const _AddOwnFoodRow({
    required this.query,
    required this.emphasized,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emphasized
          ? AppColors.accent.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(_kRowRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kRowRadius),
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 20, color: AppColors.accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  query.isEmpty
                      ? 'Add your own food'
                      : 'Add "$query" from its label',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppTypography.bodySm.copyWith(color: AppColors.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One ingredient in the meal - where a flight lands, hidden until it has.
/// Its name and calories on top; below, a mini macro tracker (a bar split by
/// each macro's share of its energy, plus the grams of each) and a grams
/// stepper. Swipe to remove.
class _IngredientCard extends StatelessWidget {
  final int id;
  final MealLogItem item;
  final bool visible;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onEditGrams;
  final VoidCallback onRemove;

  const _IngredientCard({
    super.key,
    required this.id,
    required this.item,
    required this.visible,
    required this.onMinus,
    required this.onPlus,
    required this.onEditGrams,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final muted = AppTypography.labelSm
        .copyWith(color: AppColors.onSurfaceVariant);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: visible ? kInkQuick : Duration.zero,
      child: Dismissible(
        key: ValueKey(id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onRemove(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(_kRowRadius),
          ),
          child: Icon(Icons.delete_outline_rounded, color: AppColors.error),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(_kRowRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySm.copyWith(
                            color: AppColors.highEmphasis,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _RollingNumber(item.caloriesKcal,
                      suffix: ' kcal',
                      style: AppTypography.labelSm.copyWith(
                          color: AppColors.highEmphasis,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _MacroSplitBar(item: item),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'P ${_fmt(item.proteinG)} · C ${_fmt(item.carbsG)} · '
                      'F ${_fmt(item.fatsG)}',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: muted,
                    ),
                  ),
                  _GramsStepper(
                    grams: item.grams,
                    onMinus: onMinus,
                    onPlus: onPlus,
                    onTap: onEditGrams,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 44 px bar split into protein / carbs / fat by their share of the
/// ingredient's energy - its macro profile at a glance.
class _MacroSplitBar extends StatelessWidget {
  final MealLogItem item;

  const _MacroSplitBar({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = item.proteinG * 4;
    final c = item.carbsG * 4;
    final f = item.fatsG * 9;
    final total = p + c + f;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: SizedBox(
        width: 44,
        height: 5,
        child: total <= 0
            ? ColoredBox(color: AppColors.outlineVariant.withValues(alpha: 0.4))
            : Row(
                children: [
                  for (final (value, color) in [
                    (p, _proteinColor),
                    (c, _carbsColor),
                    (f, _fatColor),
                  ])
                    if (value > 0)
                      Expanded(
                        flex: (value / total * 1000).round().clamp(1, 1000),
                        child: ColoredBox(color: color),
                      ),
                ],
              ),
      ),
    );
  }
}

class _GramsStepper extends StatelessWidget {
  final double grams;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onTap;

  const _GramsStepper({
    required this.grams,
    required this.onMinus,
    required this.onPlus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(icon: Icons.remove_rounded, onTap: onMinus),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 52),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text('${_fmt(grams)} g',
                style: AppTypography.labelSm.copyWith(
                    color: AppColors.highEmphasis,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        _StepButton(icon: Icons.add_rounded, onTap: onPlus),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      canRequestFocus: false,
      radius: 18,
      child: SizedBox(
        width: 30,
        height: 28,
        child: Icon(icon, size: 16, color: AppColors.onSurfaceVariant),
      ),
    );
  }
}

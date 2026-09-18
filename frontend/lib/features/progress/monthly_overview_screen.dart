import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../core/api/api_client.dart';
import '../../core/dev_flags.dart';
import '../onboarding/onboarding_repository.dart';
import '../onboarding/widgets/numeric_wheel_picker.dart';
import '../today/today_controller.dart';
import '../today/today_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import '../meals/meal_controller.dart';
import '../meals/meal_models.dart';
import '../meals/meal_repository.dart';
import '../splits/split_recommendation.dart';
import '../splits/splits_controller.dart';
import '../splits/splits_repository.dart';
import 'analytics_models.dart';
import 'monthly_training_chart.dart';
import 'recap_animation.dart';
import 'weekly_overview_mock.dart';

/// The Stories-style recap slideshow. Renders the Pro monthly report and, for
/// ADVANCED subscribers, the weekly report - the six shared slides plus two
/// recommendation slides (meals to add, a split to switch to) that only the
/// weekly recap carries.
class MonthlyOverviewScreen extends StatefulWidget {
  final AnalyticsRecap analytics;
  final bool preview;
  final VoidCallback onDone;
  const MonthlyOverviewScreen(
      {super.key,
      required this.analytics,
      this.preview = false,
      required this.onDone});
  @override
  State<MonthlyOverviewScreen> createState() => _MonthlyOverviewScreenState();
}

class _MonthlyOverviewScreenState extends State<MonthlyOverviewScreen> {
  final _pageController = PageController();

  // Six shared slides, plus the weekly recap's two recommendation slides.
  int get _slideCount => widget.analytics.isWeekly ? 8 : 6;
  int _page = 0;
  int _effectReplay = 0;
  bool _advancing = false;
  bool _saving = false;
  bool _loadingWeight = true;
  bool _weightEdited = false;
  double? _latestWeight;
  int _weightTenths = 700;
  String? _weightError;
  bool get _preview => (kDebugMode || kDevToolsInRelease) && widget.preview;

  @override
  void initState() {
    super.initState();
    if (_preview) {
      _setInitialWeight(widget.analytics.summary.endWeightKg);
    } else {
      _loadWeight();
    }
  }

  void _setInitialWeight(double? value) {
    if (!mounted) return;
    setState(() {
      _latestWeight = value;
      if (!_weightEdited) {
        _weightTenths = ((value ?? 70) * 10).round().clamp(300, 3000);
      }
      _loadingWeight = false;
    });
  }

  Future<void> _loadWeight() async {
    try {
      final client = context.read<ApiClient>();
      final dashboard = await TodayRepository(client).getDashboard();
      double? value = dashboard.latestWeightKg;
      value ??= (await OnboardingRepository(client).getProfile()).weightKg;
      _setInitialWeight(value);
    } catch (_) {
      if (!mounted) return;
      // A cached dashboard weight is a better fallback than the recap's old month.
      _setInitialWeight(
          context.read<TodayController>().state.data?.latestWeightKg);
    }
  }

  Future<void> _saveWeight() async {
    if (_saving || _loadingWeight) return;
    setState(() {
      _saving = true;
      _weightError = null;
    });
    try {
      final value = _weightTenths / 10;
      if (!_preview) {
        final saved =
            await context.read<TodayController>().logBodyweight(value);
        if (!saved) {
          if (mounted) {
            setState(() =>
                _weightError = 'Could not save your weight. Please try again.');
          }
          return;
        }
      }
      if (!mounted) return;
      setState(() => _latestWeight = value);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_preview
              ? 'Preview weight updated. No data saved.'
              : 'Weight saved.')));
      await _next();
    } catch (_) {
      if (mounted) {
        setState(() =>
            _weightError = 'Could not save your weight. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _next() async {
    if (_advancing || _pageController.position.isScrollingNotifier.value) {
      return;
    }
    if (_page == _slideCount - 1) {
      widget.onDone();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(_page + 1);
      return;
    }
    _advancing = true;
    try {
      await _pageController.nextPage(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic);
    } finally {
      _advancing = false;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analytics = widget.analytics;
    final summary = analytics.summary;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NotificationListener<RecapReplayNotification>(
        onNotification: (_) {
          if (_page == 0 || _page == 5) {
            setState(() => _effectReplay++);
          }
          return true;
        },
        child: Stack(fit: StackFit.expand, children: [
          SafeArea(
              child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                  AppSpacing.sm, AppSpacing.marginMobile, 0),
              child: Row(children: [
                Expanded(
                    child: _OverviewDots(count: _slideCount, index: _page)),
                const SizedBox(width: AppSpacing.md),
                IconButton(
                    tooltip: 'Close recap',
                    onPressed: _saving ? null : widget.onDone,
                    icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            if (_preview)
              Text('Preview · Sample data', style: AppTypography.labelSm),
            Expanded(
                child: PageView(
              controller: _pageController,
              physics: _saving
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                _SlideScaffold(
                  eyebrow: analytics.periodLabel,
                  icon: Icons.celebration_rounded,
                  headline: 'You showed up.\nThat matters.',
                  subhead:
                      'Congratulations on the effort you put in this ${_periodWord(analytics)}. Every logged session and every check-in is part of your story.',
                  stats: [
                    _StatTile(
                        label: 'Workouts completed',
                        value: '${summary.completedSessions}'),
                    _StatTile(
                        label: 'Days of meals logged',
                        value: '${summary.loggedMealDays}'),
                  ],
                ),
                _ImprovementsSlide(analytics: analytics),
                MonthlyTrainingChart(
                    exercises: analytics.exercises, active: _page == 2),
                _DownsidesSlide(analytics: analytics),
                _SlideScaffold(
                  eyebrow: 'A moment for you',
                  icon: Icons.favorite_outline_rounded,
                  headline: 'Take a breath.\nKeep going.',
                  subhead:
                      'An imperfect month does not erase your effort. Progress takes time. If you’d like, check in with your weight today.',
                  stats: const [],
                  footer: Column(children: [
                    if (_loadingWeight)
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator())
                    else ...[
                      Text(
                          _latestWeight == null
                              ? 'Choose your weight below'
                              : 'Latest entered weight: ${_latestWeight!.toStringAsFixed(1)} kg',
                          style: AppTypography.bodySm),
                      Semantics(
                        label: 'Weight in kilograms',
                        increasedValue:
                            ((_weightTenths + 1).clamp(300, 3000) / 10)
                                .toStringAsFixed(1),
                        decreasedValue:
                            ((_weightTenths - 1).clamp(300, 3000) / 10)
                                .toStringAsFixed(1),
                        value: (_weightTenths / 10).toStringAsFixed(1),
                        onIncrease: _saving
                            ? null
                            : () => setState(() {
                                  _weightEdited = true;
                                  _weightTenths =
                                      (_weightTenths + 1).clamp(300, 3000);
                                }),
                        onDecrease: _saving
                            ? null
                            : () => setState(() {
                                  _weightEdited = true;
                                  _weightTenths =
                                      (_weightTenths - 1).clamp(300, 3000);
                                }),
                        child: IgnorePointer(
                            ignoring: _saving,
                            child: NumericWheelPicker(
                              value: _weightTenths,
                              valueFontSize: _weightTenths >= 1000 ? 44 : 52,
                              neighborFontSize: 20,
                              min: 300,
                              max: 3000,
                              displayFormatter: (v) =>
                                  (v / 10).toStringAsFixed(1),
                              suffixLabel: 'kg',
                              onChanged: (v) => setState(() {
                                _weightEdited = true;
                                _weightTenths = v;
                              }),
                            )),
                      ),
                      if (_weightError != null)
                        Text(_weightError!,
                            style: AppTypography.bodySm
                                .copyWith(color: AppColors.error)),
                    ],
                  ]),
                ),
                _AiVerdictSlide(analytics: analytics),
                // Advanced-only: the weekly recap closes with concrete things to
                // add rather than just advice.
                if (analytics.isWeekly) ...[
                  _MealSuggestionsSlide(preview: _preview),
                  _SplitSuggestionSlide(preview: _preview),
                ],
              ]
                  .asMap()
                  .entries
                  .map((e) =>
                      TickerMode(enabled: _page == e.key, child: e.value))
                  .toList(),
            )),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile, 0,
                  AppSpacing.marginMobile, AppSpacing.md),
              child: PrimaryPillButton(
                label: _page == _slideCount - 1
                    ? 'Continue to dashboard'
                    : _page == 4
                        ? (_weightEdited
                            ? (_saving ? 'Saving…' : 'Save weight & continue')
                            : 'Skip for now')
                        : 'Next',
                onPressed: _saving
                    ? null
                    : _page == 4 && _weightEdited
                        ? _saveWeight
                        : _next,
              ),
            ),
          ])),
          if (_page == 0 || _page == 5)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRect(
                  // Keep celebration effects compact and centered so they
                  // complement the recap without dominating the screen.
                  child: FractionallySizedBox(
                    widthFactor: .55,
                    heightFactor: .55,
                    child: Opacity(
                      opacity: _page == 0 ? .65 : .55,
                      child: RecapAnimation(
                        key: ValueKey('effect-$_page-$_effectReplay'),
                        asset: _page == 0 ? 'congratulations' : 'sparks',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

String _kg(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

class _ImprovementsSlide extends StatelessWidget {
  final AnalyticsRecap analytics;
  const _ImprovementsSlide({required this.analytics});
  @override
  Widget build(BuildContext context) {
    final improved = analytics.exercises.where((e) => e.improved).toList();
    return _SlideScaffold(
      eyebrow: 'Your wins',
      icon: Icons.trending_up_rounded,
      headline: improved.isEmpty
          ? 'Every session builds your story'
          : 'Look how far you’ve come',
      subhead: improved.isEmpty
          ? 'There isn’t a comparable exercise gain to highlight yet. Keep logging weights and reps so your progress can show here.'
          : 'Your first and latest heaviest sets this ${_periodWord(analytics)}, with reps held steady or increased.',
      stats: const [],
      footer: Column(children: [
        for (final exercise in improved)
          Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: SectionCard(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(exercise.exerciseName, style: AppTypography.headlineSm),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                      '${_kg(exercise.points.first.weightKg)} kg → ${_kg(exercise.points.last.weightKg)} kg',
                      style: AppTypography.headlineLg
                          .copyWith(color: AppColors.accent)),
                  Text(
                      '${exercise.points.first.reps} reps → ${exercise.points.last.reps} reps',
                      style: AppTypography.bodySm),
                ],
              ))),
      ]),
    );
  }
}

class _DownsidesSlide extends StatelessWidget {
  final AnalyticsRecap analytics;
  const _DownsidesSlide({required this.analytics});
  @override
  Widget build(BuildContext context) {
    final missed = analytics.missedWorkoutDays;
    final over = analytics.daysOverCalorieTarget;
    final hasGaps = (missed ?? 0) > 0 || (over ?? 0) > 0;
    return _SlideScaffold(
      eyebrow: 'Room to grow',
      icon: Icons.explore_outlined,
      headline:
          hasGaps ? 'A few things to work on' : 'Keep building your rhythm',
      subhead: hasGaps
          ? 'These are useful signals for next ${_periodWord(analytics)}, not a verdict on your effort.'
          : 'No setbacks flagged in the available logs. Unlogged activity and meals are still unknown.',
      stats: const [],
      footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if ((missed ?? 0) > 0)
          SectionCard(
              child: Text(
                  '$missed missed workout days\nPast scheduled training days only. Rest days are excluded.',
                  style: AppTypography.bodyMd)),
        const SizedBox(height: AppSpacing.md),
        if ((over ?? 0) > 0)
          SectionCard(
              child: Text(
                  '$over days above your calorie target\n${analytics.totalCaloriesOverTarget ?? 0} kcal above target in total across those days.',
                  style: AppTypography.bodyMd)),
        const SizedBox(height: AppSpacing.md),
        Text(
            over == null
                ? 'Not enough nutrition data to compare against a calorie target.'
                : 'Based on ${analytics.summary.loggedMealDays} logged days and your current ${analytics.calorieTarget ?? '—'} kcal/day target. Historical targets and unlogged meals are not included.',
            style: AppTypography.bodySm),
        if (missed == null)
          Text('Missed workout history is unavailable for this report.',
              style: AppTypography.bodySm),
      ]),
    );
  }
}

/// 'week' or 'month' - the recap copy swaps between the two depending on which
/// report is being shown.
String _periodWord(AnalyticsRecap analytics) =>
    analytics.isWeekly ? 'week' : 'month';

/// A thin progress rail across the top, one bar per slide - filled bars
/// behind and including the current page, like a Stories-style recap rather
/// than the onboarding flow's discrete dot indicator (this has no "back"
/// affordance, so there's nothing to animate a capsule sliding between).
class _OverviewDots extends StatelessWidget {
  final int count;
  final int index;

  const _OverviewDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: 4,
              decoration: BoxDecoration(
                color: i <= index
                    ? AppColors.accent
                    : AppColors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
          if (i != count - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Shared layout for the first 3 slides: an icon badge, an eyebrow, a big
/// headline stat, supporting copy, then a row of smaller stat tiles.
class _SlideScaffold extends StatelessWidget {
  final String eyebrow;
  final IconData icon;
  final String headline;
  final String subhead;
  final List<_StatTile> stats;
  final Widget? footer;

  const _SlideScaffold({
    required this.eyebrow,
    required this.icon,
    required this.headline,
    required this.subhead,
    required this.stats,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.marginMobile, vertical: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RecapIcon(icon: icon),
          const SizedBox(height: AppSpacing.lg),
          SectionEyebrow(eyebrow, color: AppColors.accent),
          const SizedBox(height: AppSpacing.sm),
          Text(headline,
              textAlign: TextAlign.center,
              style: AppTypography.displayStatMobile.copyWith(fontSize: 34)),
          const SizedBox(height: AppSpacing.sm),
          Text(subhead,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant, height: 1.4)),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                Expanded(child: stats[i]),
                if (i != stats.length - 1) const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md, horizontal: AppSpacing.sm),
      child: Column(
        children: [
          Text(value, style: AppTypography.headlineSm),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: AppTypography.labelSm
                  .copyWith(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _AiVerdictSlide extends StatelessWidget {
  final AnalyticsRecap analytics;

  const _AiVerdictSlide({required this.analytics});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile, AppSpacing.lg,
          AppSpacing.marginMobile, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                const _RecapIcon(icon: Icons.auto_awesome_rounded),
                const SizedBox(height: AppSpacing.sm),
                Text('Your next chapter',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLg),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (analytics.strengths.isNotEmpty) ...[
            const SectionEyebrow('What went well'),
            const SizedBox(height: AppSpacing.sm),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final strength in analytics.strengths)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 16, color: AppColors.accent),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                              child: Text(strength,
                                  style: AppTypography.bodySm
                                      .copyWith(color: AppColors.onSurface))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (analytics.improvements.isNotEmpty) ...[
            const SectionEyebrow('Where to grow'),
            const SizedBox(height: AppSpacing.sm),
            for (final improvement in analytics.improvements)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _VerdictImprovementCard(improvement: improvement),
              ),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (analytics.focusText.isNotEmpty) ...[
            SectionEyebrow(
                analytics.isWeekly ? 'Keep going next week' : 'Keep going with',
                color: AppColors.secondary),
            const SizedBox(height: AppSpacing.sm),
            SectionCard(
              background: AppColors.surfaceContainerLow,
              child: Text(analytics.focusText,
                  style: AppTypography.bodyMd
                      .copyWith(fontStyle: FontStyle.italic)),
            ),
          ],
        ],
      ),
    );
  }
}

class _VerdictImprovementCard extends StatelessWidget {
  final AnalyticsImprovement improvement;

  const _VerdictImprovementCard({required this.improvement});

  Color _priorityColor(BuildContext context) => switch (improvement.priority) {
        'High' => AppColors.error,
        'Low' => AppColors.onSurfaceVariant,
        _ => AppColors.secondary,
      };

  @override
  Widget build(BuildContext context) {
    final priorityColor = _priorityColor(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(improvement.area,
                    style: AppTypography.labelSm
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: priorityColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.full)),
                child: Text(improvement.priority.toUpperCase(),
                    style: AppTypography.labelCaps
                        .copyWith(color: priorityColor, fontSize: 9)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(improvement.recommendation,
              style: AppTypography.bodySm.copyWith(color: AppColors.onSurface)),
        ],
      ),
    );
  }
}

/// Theme-aware, one-shot illustrations shared by both recap periods.
class _RecapIcon extends StatelessWidget {
  final IconData icon;
  const _RecapIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final celebration = icon == Icons.celebration_rounded;
    final animated = celebration ||
        icon == Icons.trending_up_rounded ||
        icon == Icons.favorite_outline_rounded ||
        icon == Icons.explore_outlined ||
        icon == Icons.auto_awesome_rounded;
    // Keep the original 152px layout slot. Only the artwork grows, so the
    // headings, stats and controls retain their original vertical positions.
    final art = SizedBox(
      width: 152,
      height: 152,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceContainerHigh,
          border: Border.all(
              color: AppColors.accent.withValues(alpha: .25), width: 2),
        ),
        child: switch (icon) {
          // The source artwork is weighted toward the lower-left corner.
          Icons.celebration_rounded => Transform.translate(
              offset: const Offset(8, -8),
              child: const RecapAnimation(asset: 'confetti')),
          Icons.trending_up_rounded => const RecapAnimation(asset: 'bar_graph'),
          Icons.favorite_outline_rounded => const Padding(
              padding: EdgeInsets.all(6),
              child: RecapAnimation(asset: 'heart_animated')),
          Icons.explore_outlined => const FittedBox(
              child: SizedBox(width: 184, height: 184, child: RecapCompass())),
          Icons.auto_awesome_rounded => const RecapAnimation(asset: 'ai_stars'),
          _ => Icon(icon, size: 88, color: AppColors.accent),
        },
      ),
    );
    return animated ? RecapAnimationStage(child: art) : art;
  }
}

/// Advanced-only recap slide: the top meal ideas from the existing
/// recommendation engine, each addable to today's plan as a Planned meal - the
/// same write path the Nutrition screen uses when activating a suggestion.
class _MealSuggestionsSlide extends StatefulWidget {
  final bool preview;
  const _MealSuggestionsSlide({required this.preview});

  @override
  State<_MealSuggestionsSlide> createState() => _MealSuggestionsSlideState();
}

class _MealSuggestionsSlideState extends State<_MealSuggestionsSlide> {
  static const _maxRecommendations = 3;

  List<MealSuggestion> _suggestions = const [];
  final Set<String> _addedIds = {};
  final Set<String> _busyIds = {};
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.preview) {
      setState(() {
        _suggestions = simulatedMealSuggestions();
        _loading = false;
      });
      return;
    }
    try {
      final api = context.read<ApiClient>();
      final all = await MealRepository(api).getSuggestions();
      // The server already ranks best-first, but sort defensively so the top
      // three are the strongest person-fit matches regardless of payload order.
      final ranked = [...all]
        ..sort((a, b) => (b.matchScore ?? 0).compareTo(a.matchScore ?? 0));
      if (!mounted) return;
      setState(() {
        _suggestions = ranked.take(_maxRecommendations).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _add(MealSuggestion suggestion) async {
    final id = suggestion.mealSuggestionId;
    if (_busyIds.contains(id) || _addedIds.contains(id)) return;
    setState(() => _busyIds.add(id));

    if (widget.preview) {
      setState(() {
        _busyIds.remove(id);
        _addedIds.add(id);
      });
      _showMessage('Preview only - no meal was added.');
      return;
    }

    try {
      final api = context.read<ApiClient>();
      await MealRepository(api).createLog(
        logDate: DateTime.now(),
        mealType: suggestion.mealType,
        title: suggestion.title,
        caloriesKcal: suggestion.caloriesKcal,
        proteinG: suggestion.proteinG,
        carbsG: suggestion.carbsG,
        fatsG: suggestion.fatsG,
        // Planned, not Logged - the user still confirms it when eaten.
        status: 'Planned',
      );
      if (!mounted) return;
      // Keep the app-wide Nutrition list in sync so the newly planned meal
      // shows immediately if the user opens that screen next.
      try {
        await context.read<MealController>().load(force: true);
      } catch (_) {
        // No shared controller in this scope (e.g. tests) - harmless.
      }
      if (!mounted) return;
      setState(() {
        _busyIds.remove(id);
        _addedIds.add(id);
      });
      _showMessage('${suggestion.title} added to today’s plan.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyIds.remove(id));
      _showMessage('Could not add that meal. Please try again.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return _SlideScaffold(
      eyebrow: 'Meals to try',
      icon: Icons.restaurant_rounded,
      headline: 'Fuel the week ahead',
      subhead:
          'Picked for your goal and current targets. Add one to today’s plan and confirm it when you eat it.',
      stats: const [],
      footer: _buildList(),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()));
    }
    if (_failed) {
      return Text('Could not load meal ideas right now.',
          style: AppTypography.bodySm);
    }
    if (_suggestions.isEmpty) {
      return Text(
          'No meal ideas yet - check back once more meals are recommended.',
          style: AppTypography.bodySm);
    }
    return Column(
      children: [
        for (final suggestion in _suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(suggestion.title, style: AppTypography.headlineSm),
                  const SizedBox(height: 2),
                  Text(
                      '${suggestion.mealType} · ${suggestion.caloriesKcal} kcal · ${suggestion.proteinG}g protein',
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant)),
                  if (suggestion.matchReason != null) ...[
                    const SizedBox(height: 4),
                    Text(suggestion.matchReason!,
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.onSurfaceVariant)),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  SecondaryPillButton(
                    icon: _addedIds.contains(suggestion.mealSuggestionId)
                        ? Icons.check_rounded
                        : Icons.add_rounded,
                    label: _addedIds.contains(suggestion.mealSuggestionId)
                        ? 'Added'
                        : _busyIds.contains(suggestion.mealSuggestionId)
                            ? 'Adding…'
                            : 'Add to today’s plan',
                    onPressed: _busyIds.contains(suggestion.mealSuggestionId) ||
                            _addedIds.contains(suggestion.mealSuggestionId)
                        ? null
                        : () => _add(suggestion),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Advanced-only recap slide: the single best-ranked split from the existing
/// split recommendation engine, switchable in one tap via the same activate
/// endpoint the Splits screen calls.
class _SplitSuggestionSlide extends StatefulWidget {
  final bool preview;
  const _SplitSuggestionSlide({required this.preview});

  @override
  State<_SplitSuggestionSlide> createState() => _SplitSuggestionSlideState();
}

class _SplitSuggestionSlideState extends State<_SplitSuggestionSlide> {
  SplitMatch? _match;
  bool _loading = true;
  bool _failed = false;
  bool _activating = false;
  bool _activated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.preview) {
      final split = simulatedRecommendedSplit();
      setState(() {
        _match = SplitMatch(
            split: split,
            score: split.matchScore ?? 0,
            reason: split.matchReason ?? '');
        _loading = false;
      });
      return;
    }
    try {
      final api = context.read<ApiClient>();
      final matches = rankSplitMatches(await SplitsRepository(api).getAll());
      if (!mounted) return;
      setState(() {
        _match = matches.isEmpty ? null : matches.first;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _activate() async {
    final match = _match;
    if (match == null || _activating || _activated) return;
    setState(() => _activating = true);

    if (widget.preview) {
      setState(() {
        _activating = false;
        _activated = true;
      });
      _showMessage('Preview only - split not activated.');
      return;
    }

    try {
      final api = context.read<ApiClient>();
      await SplitsRepository(api).activate(match.split.splitId);
      if (!mounted) return;
      // Keep the app-wide split/today state in sync so the switch is reflected
      // on the Splits and Today screens without a manual refresh.
      try {
        await context.read<SplitsController>().load(force: true);
        if (!mounted) return;
        await context.read<TodayController>().load(force: true);
      } catch (_) {
        // No shared controllers in this scope (e.g. tests) - harmless.
      }
      if (!mounted) return;
      setState(() {
        _activating = false;
        _activated = true;
      });
      _showMessage('${match.split.name} is now your active split.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _activating = false);
      _showMessage('Could not switch splits. Please try again.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return _SlideScaffold(
      eyebrow: 'A split to try',
      icon: Icons.calendar_view_week_rounded,
      headline: 'Ready for a change?',
      subhead:
          'The protocol that fits your goal and experience best right now. Switch whenever you’re ready.',
      stats: const [],
      footer: _buildCard(),
    );
  }

  Widget _buildCard() {
    if (_loading) {
      return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()));
    }
    if (_failed) {
      return Text('Could not load a split recommendation right now.',
          style: AppTypography.bodySm);
    }
    final match = _match;
    if (match == null) {
      return Text('No split recommendation yet.', style: AppTypography.bodySm);
    }
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(match.split.name, style: AppTypography.headlineSm),
          const SizedBox(height: 2),
          Text(
              '${splitCategoryLabel(match.split.category)} · ${match.split.level} · ${match.split.durationDays} days',
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant)),
          if (match.reason.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(match.reason,
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ],
          const SizedBox(height: AppSpacing.md),
          SecondaryPillButton(
            icon: _activated ? Icons.check_rounded : Icons.swap_horiz_rounded,
            label: _activated
                ? 'Active split'
                : _activating
                    ? 'Switching…'
                    : 'Switch to this split',
            onPressed: _activating || _activated ? null : _activate,
          ),
        ],
      ),
    );
  }
}

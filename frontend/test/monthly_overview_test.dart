import 'package:flutter/material.dart';
import 'package:silafit/features/progress/recap_animation.dart';
import 'package:provider/provider.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/features/today/today_controller.dart';
import 'package:silafit/features/today/today_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/features/onboarding/widgets/numeric_wheel_picker.dart';
import 'package:silafit/features/progress/analytics_models.dart';
import 'package:silafit/features/progress/monthly_overview_screen.dart';
import 'package:silafit/features/progress/monthly_training_chart.dart';
import 'package:silafit/core/widgets/section_eyebrow.dart';
import 'package:silafit/core/widgets/silen_dropdown.dart';
import 'package:silafit/features/splits/split_detail_screen.dart';

import 'support/analytics_fixtures.dart';

Future<_OverviewApi> _openRecap(WidgetTester tester,
    {AnalyticsRecap? analytics,
    bool reducedMotion = false,
    VoidCallback? onDone}) async {
  final api = _OverviewApi();
  await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<TodayController>.value(
            value: _SuccessfulWeightController(api)),
      ],
      child: MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: MonthlyOverviewScreen(
                  analytics: analytics ?? monthlyAnalyticsFixture(),
                  onDone: onDone ?? () {})))));
  await tester.pumpAndSettle();
  return api;
}

Future<void> next(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

/// Advances via whichever primary action the current slide shows - the weight
/// check-in uses "Skip for now" instead of "Next", so the weekly test can walk
/// the whole flow without special-casing each page.
Future<void> advance(WidgetTester tester) async {
  final finder = find.text('Skip for now').evaluate().isNotEmpty
      ? find.text('Skip for now')
      : find.text('Next');
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'effects stay compact and centered without changing the icon layout slot',
      (tester) async {
    await _openRecap(tester, reducedMotion: true);
    Finder asset(String name) => find.byWidgetPredicate(
        (widget) => widget is RecapAnimation && widget.asset == name);
    final screen = tester.getRect(find.byType(Scaffold));
    final effectBounds = Rect.fromCenter(
        center: screen.center,
        width: screen.width * .55,
        height: screen.height * .55);
    expect(tester.getRect(asset('congratulations')), effectBounds);
    expect(tester.widget<RecapAnimation>(asset('congratulations')).fit,
        BoxFit.cover);
    expect(tester.getSize(find.byType(RecapAnimationStage)).height, 152);
    expect(
        tester.getCenter(asset('confetti')),
        tester.getCenter(find.byType(RecapAnimationStage)) +
            const Offset(8, -8));
    expect(tester.getSize(asset('confetti')), const Size(152, 152));
    final initialKey = tester.widget(asset('congratulations')).key;
    await tester.tap(find.byType(RecapAnimationStage));
    await tester.pumpAndSettle();
    expect(tester.widget(asset('congratulations')).key, isNot(initialKey));
    for (var i = 0; i < 5; i++) {
      await advance(tester);
    }
    expect(tester.getRect(asset('sparks')), effectBounds);
    expect(tester.widget<RecapAnimation>(asset('sparks')).fit, BoxFit.cover);
    expect(asset('congratulations'), findsNothing);
    expect(tester.getSize(find.byType(RecapAnimationStage)).height, 152);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recap settles quickly and rapid taps advance only one page',
      (tester) async {
    await _openRecap(tester);
    expect(find.text('You showed up.\nThat matters.'), findsOneWidget);
    final pages = tester.widget<PageView>(find.byType(PageView));
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.text('Next'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(pages.controller!.page, 1);
    await tester.pumpAndSettle();
    expect(find.text('20 kg → 25 kg'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(pages.controller!.page, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('six screens allow skipping weight without saving',
      (tester) async {
    var finished = false;
    await _openRecap(tester,
        reducedMotion: true, onDone: () => finished = true);
    await next(tester);
    await next(tester);
    expect(find.byType(MonthlyTrainingChart), findsOneWidget);
    expect(find.text('See your effort over time'), findsOneWidget);
    await next(tester);
    expect(find.text('A few things to work on'), findsOneWidget);
    await next(tester);
    expect(find.byType(NumericWheelPicker), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('Your next chapter'), findsOneWidget);
    expect(find.text('Weight saved.'), findsNothing);
    await tester.tap(find.text('Continue to dashboard'));
    expect(finished, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wheel starts at latest entered weight, not recap end weight',
      (tester) async {
    final analytics = monthlyAnalyticsFixture();
    await _openRecap(tester, analytics: analytics, reducedMotion: true);
    for (var i = 0; i < 4; i++) {
      await next(tester);
    }
    final picker =
        tester.widget<NumericWheelPicker>(find.byType(NumericWheelPicker));
    expect(analytics.summary.endWeightKg, 82.9);
    expect(picker.value, 834);
    expect(picker.displayFormatter!(855), '85.5');
    picker.onChanged(855);
    await tester.pump();
    expect(
        tester
            .widget<NumericWheelPicker>(find.byType(NumericWheelPicker))
            .value,
        855);
    await tester.ensureVisible(find.text('Save weight & continue'));
    await tester.tap(find.text('Save weight & continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your next chapter'), findsOneWidget);
    expect(find.text('Weight saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart animation completes and flat load is described accurately',
      (tester) async {
    final exercise = monthlyAnalyticsFixture().exercises.last;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MonthlyTrainingChart(exercises: [exercise], active: true))));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(find.textContaining('stayed at 25 kg across 4 sessions'),
        findsOneWidget);
    expect(find.textContaining('40 kg'), findsOneWidget);
    expect(find.byType(SilenDropdown<int>), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old report without new fields shows honest empty states',
      (tester) async {
    final analytics = MonthlyAnalytics.fromJson({
      'year': 2026,
      'month': 8,
      'summary': {'completedSessions': 4},
      'generatedAtUtc': '2026-09-01T00:00:00Z',
    });
    await _openRecap(tester, analytics: analytics, reducedMotion: true);
    await next(tester);
    expect(find.textContaining('isn’t a comparable exercise gain'),
        findsOneWidget);
    await next(tester);
    expect(find.textContaining('No exercise sets logged'), findsOneWidget);
    await next(tester);
    expect(
        find.text(
            'Not enough nutrition data to compare against a calorie target.'),
        findsOneWidget);
    expect(find.text('Missed workout history is unavailable for this report.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'live weight save failure stays on check-in and retry saves selection',
      (tester) async {
    final api = _WeightApi();
    final today = _WeightController(api);
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<TodayController>.value(value: today),
        ],
        child: MaterialApp(
            home: MonthlyOverviewScreen(
                analytics: monthlyAnalyticsFixture(), onDone: () {}))));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await next(tester);
    }
    expect(
        tester
            .widget<NumericWheelPicker>(find.byType(NumericWheelPicker))
            .value,
        834);
    tester
        .widget<NumericWheelPicker>(find.byType(NumericWheelPicker))
        .onChanged(855);
    await tester.pump();
    await tester.ensureVisible(find.text('Save weight & continue'));
    await tester.tap(find.text('Save weight & continue'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save your weight. Please try again.'),
        findsOneWidget);
    // The edited value remains selected after a failed save, so the retry
    // action stays explicit instead of silently changing back to "skip".
    expect(find.text('Save weight & continue'), findsOneWidget);
    expect(today.savedWeights, [85.5]);
    today.succeeds = true;
    await tester.ensureVisible(find.text('Save weight & continue'));
    await tester.tap(find.text('Save weight & continue'));
    await tester.pumpAndSettle();
    expect(today.savedWeights, [85.5, 85.5]);
    expect(find.text('Your next chapter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly recap appends meal plan and next-week training slides',
      (tester) async {
    final api = await _openRecap(tester,
        analytics: weeklyAnalyticsFixture(), reducedMotion: true);
    expect(find.text('You showed up.\nThat matters.'), findsOneWidget);
    // Six shared slides, then the two Advanced-only recommendation slides.
    for (var i = 0; i < 6; i++) {
      await advance(tester);
    }
    expect(find.text('AI recommended meals for 7 days'), findsOneWidget);
    expect(find.text('DAY 1'), findsOneWidget);
    expect(find.text('DAY 7'), findsOneWidget);
    expect(find.byType(PillChip), findsWidgets);
    expect(find.text('Grilled chicken & rice bowl'), findsOneWidget);
    expect(find.text('Macros · P 48g · C 62g · F 18g'), findsOneWidget);
    expect(
        find.text(
            'Ingredients · Chicken breast · brown rice · broccoli · olive oil · +2 more'),
        findsOneWidget);
    expect(find.text('Add to Day 1'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DAY 7'));
    await tester.pumpAndSettle();
    expect(find.text('Add to Day 7'), findsWidgets);
    await advance(tester);
    expect(find.text('Stay with your current split'), findsOneWidget);
    expect(find.text('Push · Pull · Legs'), findsOneWidget);
    expect(find.text('Recovery day'), findsWidgets);
    expect(find.text('Review my split'), findsOneWidget);
    expect(find.text('Switch to this split'), findsNothing);
    expect(find.text('Continue to dashboard'), findsOneWidget);
    final requestsBeforeOpen = api.splitDetailRequests;
    expect(requestsBeforeOpen, greaterThanOrEqualTo(1));
    await tester.ensureVisible(find.text('Review my split'));
    await tester.tap(find.text('Review my split'));
    await tester.pumpAndSettle();
    expect(find.byType(SplitDetailScreen), findsOneWidget);
    expect(find.text('WEEKLY BREAKDOWN'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Opening the detail reuses the already loaded preview payload instead of
    // starting a second request that can leave this screen spinning.
    expect(api.splitDetailRequests, requestsBeforeOpen);
    expect(tester.takeException(), isNull);
  });

  test('weekly analytics model parses its period metadata', () {
    final weekly = WeeklyAnalytics.fromJson({
      'year': 2026,
      'weekNumber': 37,
      'weekStartUtc': '2026-09-07T00:00:00Z',
      'weekEndUtc': '2026-09-13T00:00:00Z',
      'summary': {'completedSessions': 3},
      'focusForNextWeek': 'Add one leg day.',
      'generatedAtUtc': '2026-09-13T12:00:00Z',
    });
    expect(weekly.isWeekly, isTrue);
    expect(weekly.periodLabel, 'Week 37 · Sep 7 – Sep 13, 2026');
    expect(weekly.focusText, 'Add one leg day.');
  });

  test('exercise improvement accounts for reps and handles sparse history', () {
    MonthlyExercise exercise(List<(double, int)> sets) => MonthlyExercise(
            exerciseId: '1',
            exerciseName: 'Press',
            recordWeightKg: 40,
            points: [
              for (var i = 0; i < sets.length; i++)
                MonthlyExercisePoint(
                    dateUtc: DateTime.utc(2026, 8, i + 1),
                    weightKg: sets[i].$1,
                    reps: sets[i].$2)
            ]);
    expect(exercise([(20, 10), (25, 10)]).improved, isTrue);
    expect(exercise([(20, 10), (25, 5)]).improved, isFalse);
    expect(exercise([(25, 10), (25, 12)]).improved, isTrue);
    expect(exercise([(25, 10), (25, 10), (25, 10)]).steadyLoad, isTrue);
    expect(exercise([(25, 10)]).improved, isFalse);
    expect(exercise([]).improved, isFalse);
  });
}

class _WeightApi implements ApiClient {
  @override
  Future<T> get<T>(String path, T Function(dynamic) parse,
      {Map<String, String>? query}) async {
    return parse(<String, dynamic>{
      'latestWeightKg': 83.4,
      'session': <String, dynamic>{}
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OverviewApi implements ApiClient {
  int splitDetailRequests = 0;

  @override
  Future<T> get<T>(String path, T Function(dynamic) parse,
      {Map<String, String>? query}) async {
    if (path == '/splits/split-ppl') splitDetailRequests++;
    final Object payload = switch (path) {
      '/today' => <String, dynamic>{
          // Deliberately differs from the recap's 82.9 kg month-end value: the
          // check-in must start from the user's most recently entered weight.
          'latestWeightKg': 83.4,
          'session': <String, dynamic>{},
          'activeSplit': <String, dynamic>{
            'splitId': 'split-ppl',
            'name': 'Push · Pull · Legs',
            'durationDays': 7,
            'activatedAtUtc': '2026-09-21T00:00:00Z',
          },
        },
      '/meals/suggestions' => <Map<String, dynamic>>[
          {
            'mealSuggestionId': 'meal-oats',
            'title': 'Protein berry oats',
            'mealType': 'Breakfast',
            'caloriesKcal': 510,
            'proteinG': 34,
            'carbsG': 67,
            'fatsG': 12,
            'ingredientPreview':
                'Rolled oats · whey protein · blueberries · almond milk',
            'ingredientCount': 5,
            'matchScore': 96,
            'matchReason': 'Balanced start to the day',
          },
          {
            'mealSuggestionId': 'meal-chicken',
            'title': 'Grilled chicken & rice bowl',
            'mealType': 'Lunch',
            'caloriesKcal': 620,
            'proteinG': 48,
            'carbsG': 62,
            'fatsG': 18,
            'ingredientPreview':
                'Chicken breast · brown rice · broccoli · olive oil',
            'ingredientCount': 6,
            'matchScore': 94,
            'matchReason': 'High protein · fits your lunch calorie target',
          },
          {
            'mealSuggestionId': 'meal-salmon',
            'title': 'Salmon & roasted vegetables',
            'mealType': 'Dinner',
            'caloriesKcal': 680,
            'proteinG': 46,
            'carbsG': 48,
            'fatsG': 30,
            'ingredientPreview': 'Salmon · sweet potato · zucchini · olive oil',
            'ingredientCount': 4,
            'matchScore': 92,
            'matchReason': 'Protein and healthy fats for dinner',
          },
        ],
      '/splits/split-ppl' => <String, dynamic>{
          'split': <String, dynamic>{
            'splitId': 'split-ppl',
            'name': 'Push · Pull · Legs',
            'category': 'PushPullLegs',
            'level': 'Intermediate',
            'durationDays': 6,
            'isSystemDefault': true,
            'recommendedGoal': 'BuildMuscle',
            'matchesGoal': true,
            'matchScore': 92,
            'matchReason':
                'Matched to your Build Muscle goal · Intermediate · 6 days',
          },
          'days': <Map<String, dynamic>>[
            for (var i = 0; i < 7; i++)
              {
                'day': <String, dynamic>{
                  'splitDayId': 'day-$i',
                  'dayIndex': i,
                  'title': i == 3 ? 'Recovery' : 'Training day ${i + 1}',
                  'estimatedMinutes': i == 3 ? 0 : 60,
                  'isRestDay': i == 3,
                },
                'exercises': <Map<String, dynamic>>[],
              },
          ],
        },
      _ => throw StateError('Unexpected GET $path'),
    };
    return parse(payload);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SuccessfulWeightController extends TodayController {
  _SuccessfulWeightController(ApiClient api) : super(TodayRepository(api));

  @override
  Future<bool> logBodyweight(double weightKg) async => true;
}

class _WeightController extends TodayController {
  bool succeeds = false;
  final savedWeights = <double>[];
  _WeightController(ApiClient api) : super(TodayRepository(api));
  @override
  Future<bool> logBodyweight(double weightKg) async {
    savedWeights.add(weightKg);
    return succeeds;
  }
}

import 'package:flutter/material.dart';
import 'package:silafit/features/progress/recap_animation.dart';
import 'package:provider/provider.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/features/today/today_controller.dart';
import 'package:silafit/features/today/today_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/features/onboarding/widgets/numeric_wheel_picker.dart';
import 'package:silafit/features/progress/analytics_models.dart';
import 'package:silafit/features/progress/monthly_overview_mock.dart';
import 'package:silafit/features/progress/monthly_overview_screen.dart';
import 'package:silafit/features/progress/monthly_training_chart.dart';
import 'package:silafit/features/progress/weekly_overview_mock.dart';

Future<void> openRecap(WidgetTester tester,
    {AnalyticsRecap? analytics,
    bool reducedMotion = false,
    VoidCallback? onDone}) async {
  await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: MonthlyOverviewScreen(
              analytics: analytics ?? buildSimulatedMonthlyAnalytics(),
              preview: true,
              onDone: onDone ?? () {}))));
  await tester.pumpAndSettle();
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
  testWidgets('effects stay compact and centered without changing the icon layout slot',
      (tester) async {
    await openRecap(tester, reducedMotion: true);
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
    expect(tester.getCenter(asset('confetti')),
        tester.getCenter(find.byType(RecapAnimationStage)) + const Offset(8, -8));
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
    await openRecap(tester);
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
    await openRecap(tester, reducedMotion: true, onDone: () => finished = true);
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

  testWidgets('wheel starts at latest weight and preview save advances',
      (tester) async {
    final analytics = buildSimulatedMonthlyAnalytics();
    await openRecap(tester, analytics: analytics, reducedMotion: true);
    for (var i = 0; i < 4; i++) {
      await next(tester);
    }
    final picker =
        tester.widget<NumericWheelPicker>(find.byType(NumericWheelPicker));
    expect(picker.value, (analytics.summary.endWeightKg! * 10).round());
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
    expect(find.text('Preview weight updated. No data saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart animation completes and flat load is described accurately',
      (tester) async {
    final exercise = buildSimulatedMonthlyAnalytics().exercises.last;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MonthlyTrainingChart(exercises: [exercise], active: true))));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(find.textContaining('stayed at 25 kg across 4 sessions'),
        findsOneWidget);
    expect(find.textContaining('40 kg'), findsOneWidget);
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
    await openRecap(tester, analytics: analytics, reducedMotion: true);
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
                analytics: buildSimulatedMonthlyAnalytics(), onDone: () {}))));
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
    expect(find.text('Skip for now'), findsOneWidget);
    expect(today.savedWeights, [85.5]);
    today.succeeds = true;
    await tester.ensureVisible(find.text('Save weight & continue'));
    await tester.tap(find.text('Save weight & continue'));
    await tester.pumpAndSettle();
    expect(today.savedWeights, [85.5, 85.5]);
    expect(find.text('Your next chapter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly recap appends meal and split recommendation slides',
      (tester) async {
    await openRecap(tester,
        analytics: buildSimulatedWeeklyAnalytics(), reducedMotion: true);
    expect(find.text('You showed up.\nThat matters.'), findsOneWidget);
    // Six shared slides, then the two Advanced-only recommendation slides.
    for (var i = 0; i < 6; i++) {
      await advance(tester);
    }
    expect(find.text('Fuel the week ahead'), findsOneWidget);
    expect(find.text('Grilled chicken & rice bowl'), findsOneWidget);
    expect(find.text('Add to today’s plan'), findsWidgets);
    await advance(tester);
    expect(find.text('Ready for a change?'), findsOneWidget);
    expect(find.text('Switch to this split'), findsOneWidget);
    expect(find.text('Continue to dashboard'), findsOneWidget);
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

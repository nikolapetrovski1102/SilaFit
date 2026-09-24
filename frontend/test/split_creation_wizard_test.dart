import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/features/exercises/exercises_models.dart';
import 'package:silafit/features/exercises/exercises_repository.dart';
import 'package:silafit/features/splits/split_creation_wizard_screen.dart';
import 'package:silafit/features/splits/splits_repository.dart';

class _FakeSplits extends SplitsRepository {
  _FakeSplits() : super(ApiClient(sessionStore: SessionStore()));

  final calls = <String>[];

  @override
  Future<String?> createOrUpdate({
    String? splitId,
    required String name,
    required String category,
    required String level,
    required int durationDays,
    String? description,
    String? heroImageUrl,
    String? recommendedGoal,
  }) async {
    calls.add('split:$name');
    return 'split-1';
  }

  @override
  Future<String?> saveDay({
    String? splitDayId,
    required String splitId,
    required int dayIndex,
    required String title,
    String? focusLabel,
    int estimatedMinutes = 60,
    bool isRestDay = false,
  }) async {
    calls.add('day:$dayIndex:$title:${isRestDay ? 'rest' : 'train'}');
    return 'day-$dayIndex';
  }

  @override
  Future<String?> saveDayExercise({
    String? splitDayExerciseId,
    required String splitDayId,
    required String exerciseId,
    required int sortOrder,
    required int targetSets,
    required int targetRepsLow,
    required int targetRepsHigh,
  }) async {
    calls.add('exercise:$splitDayId:$exerciseId');
    return 'sde-$exerciseId';
  }
}

class _FakeExercises extends ExercisesRepository {
  _FakeExercises() : super(ApiClient(sessionStore: SessionStore()));

  static const bench = ExerciseSummary(
      exerciseId: 'bench',
      name: 'Bench Press',
      muscleGroup: 'Chest',
      isCompound: true);
  static const fly = ExerciseSummary(
      exerciseId: 'fly',
      name: 'Cable Fly',
      muscleGroup: 'Chest',
      isCompound: false);

  @override
  Future<List<ExerciseSummary>> suggestions(
          {List<String>? muscleGroups, int? limit}) async =>
      const [bench, fly];

  @override
  Future<List<ExerciseSummary>> search(
          {String? muscleGroup, String? search}) async =>
      const [fly];
}

String? fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller?.text;

void main() {
  testWidgets('name -> day -> exercises flow with one field', (tester) async {
    final splits = _FakeSplits();
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<SplitsRepository>.value(value: splits),
        Provider<ExercisesRepository>.value(value: _FakeExercises()),
      ],
      child: const MaterialApp(
          home: SplitCreationWizardScreen(existingSplitCount: 2)),
    ));
    await tester.pumpAndSettle();

    // Name preset, fully selected.
    expect(fieldText(tester), 'Awesome Split 3');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    // Name lifted into the title; same field now holds the day preset.
    expect(find.text('Awesome Split 3'), findsOneWidget);
    expect(fieldText(tester), 'Awesome Day 1');
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Push');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    expect(find.text('Push'), findsOneWidget);
    expect(find.text('DAY 1 OF 7'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);

    // Tap a suggestion - it flies into the day's chips.
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsOneWidget);

    // Search + keyboard action adds the top match.
    await tester.enterText(find.byType(TextField), 'fly');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Empty field + done moves to the next day.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(fieldText(tester), 'Awesome Day 2');

    await tester.tap(find.text('Rest day'));
    await tester.pumpAndSettle();
    expect(fieldText(tester), 'Awesome Day 3');

    expect(splits.calls, [
      'split:Awesome Split 3',
      'day:1:Push:train',
      'exercise:day-1:bench',
      'exercise:day-1:fly',
      'day:2:Rest day:rest',
    ]);
  });

  testWidgets('big input shrinks to stay on one line before wrapping',
      (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<SplitsRepository>.value(value: _FakeSplits()),
        Provider<ExercisesRepository>.value(value: _FakeExercises()),
      ],
      child: const MaterialApp(home: SplitCreationWizardScreen()),
    ));
    await tester.pumpAndSettle();

    double fontSize() =>
        tester.widget<TextField>(find.byType(TextField)).style!.fontSize!;
    double fieldHeight() => tester.getSize(find.byType(EditableText)).height;

    // Short text: full size, one line.
    await tester.enterText(find.byType(TextField), 'Push');
    await tester.pump();
    expect(fontSize(), 56);
    expect(fieldHeight(), closeTo(56 * 1.1, 1));

    // Longer text: shrinks but still one line. (The test font draws every
    // glyph a full em wide, so strings here are shorter than on device.)
    await tester.enterText(find.byType(TextField), 'Push Pull');
    await tester.pump();
    final size = fontSize();
    expect(size, lessThan(56));
    expect(fieldHeight(), closeTo(size * 1.1, 1));

    // Very long text: bottoms out at the minimum, then wraps.
    await tester.enterText(
        find.byType(TextField), 'My Very Long Upper Lower Hypertrophy Block');
    await tester.pump();
    expect(fontSize(), 34);
    expect(fieldHeight(), greaterThan(34 * 1.1 * 1.5));
  });
}

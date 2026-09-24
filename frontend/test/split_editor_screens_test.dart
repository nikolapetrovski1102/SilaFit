import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/features/exercises/exercises_models.dart';
import 'package:silafit/features/exercises/exercises_repository.dart';
import 'package:silafit/features/splits/split_builder_screen.dart';
import 'package:silafit/features/splits/split_day_editor_screen.dart';
import 'package:silafit/features/splits/splits_controller.dart';
import 'package:silafit/features/splits/splits_models.dart';
import 'package:silafit/features/splits/splits_repository.dart';
import 'package:silafit/features/splits/widgets/muscle_focus_field.dart';

/// An in-memory split the fake repository edits in place.
class _FakeSplits extends SplitsRepository {
  _FakeSplits() : super(ApiClient(sessionStore: SessionStore()));

  final calls = <String>[];
  String name = 'Push Pull Legs';
  final days = <SplitDay>[
    const SplitDay(
        splitDayId: 'd1',
        dayIndex: 1,
        title: 'Push',
        estimatedMinutes: 60,
        isRestDay: false),
  ];
  final exercises = <String, List<SplitDayExercise>>{
    'd1': [
      const SplitDayExercise(
          splitDayExerciseId: 'x1',
          exerciseId: 'bench',
          name: 'Bench Press',
          sortOrder: 0,
          targetSets: 3,
          targetRepsLow: 8,
          targetRepsHigh: 12),
    ],
  };

  @override
  Future<SplitDetail> getDetail(String splitId) async => SplitDetail(
        split: WorkoutSplit(
          splitId: splitId,
          name: name,
          category: 'Custom',
          level: 'Intermediate',
          durationDays: 7,
          isSystemDefault: false,
          isEditableByMe: true,
        ),
        days: [
          for (final d in days)
            SplitDayWithExercises(
                day: d, exercises: [...?exercises[d.splitDayId]]),
        ],
      );

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
    this.name = name;
    return splitId ?? 'split-1';
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
    final id = splitDayId ?? 'd${days.length + 1}';
    calls.add('day:$id:$title:${isRestDay ? 'rest' : 'train'}');
    days.removeWhere((d) => d.splitDayId == id);
    days.add(SplitDay(
        splitDayId: id,
        dayIndex: dayIndex,
        title: title,
        focusLabel: focusLabel,
        estimatedMinutes: estimatedMinutes,
        isRestDay: isRestDay));
    return id;
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
    final id = splitDayExerciseId ?? 'x-$exerciseId';
    final list = exercises.putIfAbsent(splitDayId, () => []);
    list.removeWhere((e) => e.splitDayExerciseId == id);
    list.add(SplitDayExercise(
        splitDayExerciseId: id,
        exerciseId: exerciseId,
        name: exerciseId == 'fly' ? 'Cable Fly' : exerciseId,
        sortOrder: sortOrder,
        targetSets: targetSets,
        targetRepsLow: targetRepsLow,
        targetRepsHigh: targetRepsHigh));
    return id;
  }

  @override
  Future<void> deleteDayExercise(String splitDayExerciseId) async {
    calls.add('delete-exercise:$splitDayExerciseId');
    for (final list in exercises.values) {
      list.removeWhere((e) => e.splitDayExerciseId == splitDayExerciseId);
    }
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

Widget _app(Widget home, SplitsRepository splits) => MultiProvider(
      providers: [
        Provider<SplitsRepository>.value(value: splits),
        Provider<ExercisesRepository>.value(value: _FakeExercises()),
      ],
      child: MaterialApp(home: home),
    );

String? _textOf(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller?.text;

void main() {
  testWidgets('split editor: no app bar, name saves on blur, days listed',
      (tester) async {
    final splits = _FakeSplits();
    final controller = SplitBuilderController(splits, splitId: 'split-1');
    await tester
        .pumpWidget(_app(SplitBuilderScreen(controller: controller), splits));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    final nameField = find.byType(TextField).first;
    expect(_textOf(tester, nameField), 'Push Pull Legs');
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Add day'), findsOneWidget);

    // Focusing and leaving without a change doesn't save.
    await tester.tap(nameField);
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(splits.calls, isEmpty);

    await tester.enterText(nameField, 'Upper Lower');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(splits.calls, ['split:Upper Lower']);
  });

  testWidgets('day editor: search adds a chip, x removes it, rest toggles',
      (tester) async {
    final splits = _FakeSplits();
    final controller = SplitBuilderController(splits, splitId: 'split-1');
    await controller.load();
    await tester.pumpWidget(_app(
        SplitDayEditorScreen(
            builderController: controller,
            splitId: 'split-1',
            splitDayId: 'd1'),
        splits));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('3×8–12'), findsOneWidget); // Bench Press chip
    // Bench is already on the day, so only the fly is suggested.
    expect(find.text('Cable Fly'), findsOneWidget);

    await tester.tap(find.text('Cable Fly'));
    await tester.pumpAndSettle();
    expect(splits.calls, ['exercise:d1:fly']);
    expect(find.text('3×8–12'), findsNWidgets(2));

    // Remove the fly again from its chip.
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    expect(splits.calls.last, 'delete-exercise:x-fly');
    expect(find.text('3×8–12'), findsOneWidget);

    await tester.tap(find.text('Rest'));
    await tester.pumpAndSettle();
    expect(splits.calls.last, 'day:d1:Push:rest');
    expect(find.text('Add exercise'), findsNothing);
  });

  testWidgets('new day: preset title creates the day exactly once',
      (tester) async {
    final splits = _FakeSplits();
    final controller = SplitBuilderController(splits, splitId: 'split-1');
    await controller.load();
    await tester.pumpWidget(_app(
        SplitDayEditorScreen(builderController: controller, splitId: 'split-1'),
        splits));
    await tester.pumpAndSettle();

    final title = find.byType(TextField).first;
    expect(_textOf(tester, title), 'Awesome Day 2');

    // Submit moves focus on to the search - the blur must not save again.
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(splits.calls, ['day:d2:Awesome Day 2:train']);
    expect(find.text('Add exercise'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('day editor: muscle focus dropdown picks up to 4, saves on blur',
      (tester) async {
    final splits = _FakeSplits();
    final controller = SplitBuilderController(splits, splitId: 'split-1');
    await controller.load();
    await tester.pumpWidget(_app(
        SplitDayEditorScreen(
            builderController: controller,
            splitId: 'split-1',
            splitDayId: 'd1'),
        splits));
    await tester.pumpAndSettle();

    final field = find.widgetWithText(TextField, 'Muscle focus');
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.textContaining('PICK UP TO 4'), findsOneWidget);

    Finder option(String label) => find.descendant(
        of: find.byType(ListView).first, matching: find.text(label));
    await tester.tap(option('Chest'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1/4'), findsOneWidget);

    // Typing filters the list; submit takes the first match.
    for (final query in ['shoul', 'tric', 'core']) {
      await tester.enterText(find.byType(TextField).at(1), query);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('TAP ONE TO DROP IT'), findsOneWidget);
    // Full: a fifth pick is ignored.
    await tester.tap(option('Back'));
    await tester.pumpAndSettle();
    expect(splits.days.first.focusLabel, isNull);
    expect(splits.calls, isEmpty);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.textContaining('PICK UP TO'), findsNothing);
    expect(splits.calls, ['day:d1:Push:train']);
    expect(splits.days.first.focusLabel, 'Chest, Shoulders, Triceps & Core');
  });

  test('muscle targets round-trip through the focus label', () {
    expect(parseMuscleTargets('chest & triceps'), ['Chest', 'Triceps']);
    expect(parseMuscleTargets('Back, Biceps and rear delts'),
        ['Back', 'Biceps', 'Rear Delts']);
    expect(formatMuscleTargets(['Quads', 'Glutes', 'Calves']),
        'Quads, Glutes & Calves');
  });

  testWidgets('opening a day flies its title from the tile', (tester) async {
    final splits = _FakeSplits();
    final controller = SplitBuilderController(splits, splitId: 'split-1');
    await tester
        .pumpWidget(_app(SplitBuilderScreen(controller: controller), splits));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // Mid-flight: the title is drawn by the hero shuttle.
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(SplitDayEditorScreen), findsOneWidget);
    expect(find.text('DAY 1').hitTestable(), findsOneWidget);

    Navigator.of(tester.element(find.byType(SplitDayEditorScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(SplitDayEditorScreen), findsNothing);
  });
}

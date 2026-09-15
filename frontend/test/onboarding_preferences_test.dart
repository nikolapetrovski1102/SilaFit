import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/features/notifications/notifications_repository.dart';
import 'package:silafit/features/onboarding/onboarding_controller.dart';
import 'package:silafit/features/onboarding/onboarding_models.dart';
import 'package:silafit/features/onboarding/onboarding_repository.dart';
import 'package:silafit/features/onboarding/widgets/age_wheel_picker.dart';
import 'package:silafit/features/onboarding/widgets/arc_rating_slider.dart';
import 'package:silafit/features/onboarding/widgets/question_scaffold.dart';
import 'package:silafit/features/onboarding/widgets/training_preference_question.dart';

class RecordingClient extends ApiClient {
  Map<String, dynamic>? saved;
  RecordingClient() : super(sessionStore: SessionStore());
  @override
  Future<T> put<T>(String path, T Function(dynamic) parse,
      {Object? body}) async {
    expect(path, '/profile');
    saved = body as Map<String, dynamic>?;
    return parse(body);
  }
}

void main() {
  test('all five answers round trip in the profile request', () async {
    final client = RecordingClient();
    final controller = OnboardingController(
        OnboardingRepository(client), NotificationsRepository(client),
        autoAdvanceEnabled: false);
    addTearDown(controller.dispose);
    controller.selectGender('Female');
    controller.selectGoal('BuildMuscle');
    expect(await controller.submit(), isFalse);
    expect(client.saved, isNull);
    controller.setTrainingDaysPerWeek(3);
    controller.setTrainingExperience('Intermediate');
    controller.setEquipmentAccess('Dumbbells');
    controller.setDailyActivityLevel('LightlyActive');
    expect(await controller.submit(), isTrue);
    final profile = UserProfile.fromJson(client.saved);
    expect(profile.isComplete, isTrue);
    expect(profile.trainingDaysPerWeek, 3);
    expect(profile.sessionDurationMinutes, 45);
    expect(profile.trainingExperience, 'Intermediate');
    expect(profile.equipmentAccess, 'Dumbbells');
    expect(profile.dailyActivityLevel, 'LightlyActive');
  });

  test('legacy profiles remain readable and existing answers are prefilled',
      () {
    final profile = UserProfile.fromJson({
      'gender': 'Male',
      'ageYears': 42,
      'heightCm': 181,
      'weightKg': 86,
      'goal': 'MaintainActive',
    });
    expect(profile.isComplete, isFalse);
    final client = RecordingClient();
    final controller = OnboardingController(
        OnboardingRepository(client), NotificationsRepository(client),
        initialProfile: profile);
    addTearDown(controller.dispose);
    expect(controller.ageYears, 42);
    expect(controller.weightKg, 86);
    expect(controller.goal, 'MaintainActive');
    expect(controller.trainingExperience, isNull);
    expect(controller.sessionDurationMinutes, 45);
  });

  testWidgets('training days scroll on a small screen and selection persists',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = RecordingClient();
    final controller = OnboardingController(
        OnboardingRepository(client), NotificationsRepository(client),
        autoAdvanceEnabled: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TrainingPreferenceQuestion(
                controller: controller,
                step: OnboardingStep.trainingDays,
                progressStep: 6,
                progressStepCount: 11,
                onBack: () {},
                onNext: () {}))));
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6+ days'));
    await tester.pumpAndSettle();
    expect(controller.trainingDaysPerWeek, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('age assessment keeps the large wheel inside a compact screen',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var age = 18;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuestionScaffold(
          onBack: () {},
          progressStep: 2,
          progressStepCount: 11,
          headline: 'What is your age?',
          body: StatefulBuilder(builder: (context, setState) {
            return Center(
              child: AgeWheelPicker(
                value: age,
                min: 13,
                max: 100,
                onChanged: (value) => setState(() => age = value),
              ),
            );
          }),
          ctaLabel: 'Continue',
          onCta: () {},
        ),
      ),
    ));

    expect(find.text('Assessment'), findsOneWidget);
    expect(find.byKey(const Key('assessment-step-badge')), findsOneWidget);
    expect(find.text('What is your age?'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fitness arc is usable without overflowing a compact screen',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? selected = 'Intermediate';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuestionScaffold(
          onBack: () {},
          progressStep: 8,
          progressStepCount: 11,
          headline: 'How would you rate your fitness level?',
          body: StatefulBuilder(builder: (context, setState) {
            return ArcRatingSlider(
              values: const ['Beginner', 'Intermediate', 'Advanced'],
              labels: const {
                'Beginner': 'Getting started',
                'Intermediate': 'Somewhat athletic',
                'Advanced': 'Very athletic',
              },
              displayNumbers: const [1, 3, 5],
              selected: selected,
              onSelected: (value) => setState(() => selected = value),
            );
          }),
          ctaLabel: 'Continue',
          onCta: () {},
        ),
      ),
    ));

    expect(find.text('Somewhat athletic'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    final sliderRect = tester.getRect(find.byType(ArcRatingSlider));
    final thumbRect =
        tester.getRect(find.byKey(const Key('fitness-rating-thumb')));
    expect(thumbRect.left, greaterThanOrEqualTo(sliderRect.left));
    expect(thumbRect.right, lessThanOrEqualTo(sliderRect.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fitness arc haptics fire and end thumb stays in bounds',
      (tester) async {
    String? selected = 'Intermediate';
    var hapticCount = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') hapticCount++;
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 335,
            child: StatefulBuilder(builder: (context, setState) {
              return ArcRatingSlider(
                values: const ['Beginner', 'Intermediate', 'Advanced'],
                labels: const {
                  'Beginner': 'Getting started',
                  'Intermediate': 'Somewhat athletic',
                  'Advanced': 'Very athletic',
                },
                displayNumbers: const [1, 3, 5],
                selected: selected,
                onSelected: (value) => setState(() => selected = value),
              );
            }),
          ),
        ),
      ),
    ));

    await tester.drag(
      find.byKey(const Key('fitness-rating-gesture')),
      const Offset(150, 0),
      touchSlopX: 0,
    );
    await tester.pumpAndSettle();

    expect(selected, 'Advanced');
    expect(hapticCount, greaterThan(0));
    final sliderRect = tester.getRect(find.byType(ArcRatingSlider));
    final thumbRect =
        tester.getRect(find.byKey(const Key('fitness-rating-thumb')));
    expect(thumbRect.left, greaterThanOrEqualTo(sliderRect.left));
    expect(thumbRect.right, lessThanOrEqualTo(sliderRect.right));
    expect(tester.takeException(), isNull);
  });
}

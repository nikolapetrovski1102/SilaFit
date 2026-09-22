import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/features/onboarding/widgets/tour_guide_card.dart';

void main() {
  testWidgets('TourSpotlightOverlay finds target key and triggers callbacks',
      (tester) async {
    final targetKey = GlobalKey();
    var nextPressed = false;
    var skipPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 100,
                left: 20,
                width: 300,
                height: 150,
                child: KeyedSubtree(
                  key: targetKey,
                  child: Container(color: Colors.blue),
                ),
              ),
              Positioned.fill(
                child: TourSpotlightOverlay(
                  targetKey: targetKey,
                  stepIndex: 0,
                  stepCount: 5,
                  title: 'Test Headline',
                  description: 'Test Description',
                  onNext: () => nextPressed = true,
                  onSkip: () => skipPressed = true,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Initial pump
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify card content renders
    expect(find.text('Test Headline'), findsOneWidget);
    expect(find.text('Test Description'), findsOneWidget);
    expect(find.text('01 / 05'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    // Tap Next
    await tester.tap(find.text('Next'));
    expect(nextPressed, isTrue);

    // Tap Skip
    await tester.tap(find.text('Skip'));
    expect(skipPressed, isTrue);
  });

  testWidgets(
      'TourSpotlightOverlay positions card at top when target is in lower screen',
      (tester) async {
    final targetKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 20,
                left: 20,
                width: 300,
                height: 200,
                child: KeyedSubtree(
                  key: targetKey,
                  child: Container(color: Colors.red),
                ),
              ),
              Positioned.fill(
                child: TourSpotlightOverlay(
                  targetKey: targetKey,
                  stepIndex: 4,
                  stepCount: 5,
                  title: 'Bottom Target',
                  description: 'Target is near bottom',
                  onNext: () {},
                  onSkip: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Card should be rendered
    expect(find.text('Bottom Target'), findsOneWidget);

    // Card should be placed near top of screen
    final cardTopLeft = tester.getTopLeft(find.byType(TourGuideCard));
    expect(cardTopLeft.dy, lessThan(100));
  });
}

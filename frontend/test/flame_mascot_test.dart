import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/core/widgets/mascot/flame_mascot.dart';
import 'package:silafit/core/widgets/mascot/streak_flame.dart';
import 'package:silafit/core/widgets/mascot/talking_mascot.dart';
import 'package:silafit/features/onboarding/onboarding_controller.dart';
import 'package:silafit/features/onboarding/onboarding_mascot_lines.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  test('streak flame grows at 1, 7 and 30 days', () {
    expect(StreakFlame.artFor(0), FlameArt.sleepy);
    expect(StreakFlame.artFor(1), FlameArt.spark);
    expect(StreakFlame.artFor(6), FlameArt.spark);
    expect(StreakFlame.artFor(7), FlameArt.flame);
    expect(StreakFlame.artFor(29), FlameArt.flame);
    expect(StreakFlame.artFor(30), FlameArt.blaze);
    expect(StreakFlame.artFor(365), FlameArt.blaze);
    expect(StreakFlame.nextStageAt(3), 7);
    expect(StreakFlame.nextStageAt(12), 30);
    expect(StreakFlame.nextStageAt(30), isNull);
  });

  test('flame art resolves a light and a dark asset', () {
    expect(FlameArt.spark.assetPathFor(Brightness.dark),
        'assets/mascot/flame/dark/spark.png');
    expect(FlameArt.spark.assetPathFor(Brightness.light),
        'assets/mascot/flame/light/spark.png');
  });

  test('every onboarding question has a mascot line', () {
    for (final step in OnboardingStep.values) {
      final line = mascotLineFor(step);
      if (step == OnboardingStep.intro) {
        expect(line, isNull);
      } else {
        expect(line, isNotNull, reason: '$step');
        expect(line!.text.length, lessThanOrEqualTo(60), reason: '$step');
      }
    }
  });

  testWidgets('flame mascot picks the asset for the ambient theme',
      (tester) async {
    await tester.pumpWidget(_host(const FlameMascot(FlameArt.smug, size: 40),
        brightness: Brightness.light));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName,
        'assets/mascot/flame/light/smug.png');
  });

  testWidgets('talking mascot types its line and announces it whole',
      (tester) async {
    const line = MascotLine(FlameArt.laughing, 'Hey there, champ!');
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(const TalkingMascot(line: line)));
    expect(find.bySemanticsLabel('Silen says: Hey there, champ!'),
        findsOneWidget);
    await tester.pumpAndSettle();
    final rich = tester.widget<Text>(find.byType(Text)).textSpan as TextSpan;
    expect((rich.children!.first as TextSpan).text, line.text);
    semantics.dispose();
  });

  testWidgets('talking mascot shows the full line at once with reduced motion',
      (tester) async {
    const line = MascotLine(FlameArt.smug, 'No animations here.');
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: _host(const TalkingMascot(line: line)),
    ));
    final rich = tester.widget<Text>(find.byType(Text)).textSpan as TextSpan;
    expect((rich.children!.first as TextSpan).text, line.text);
  });
}

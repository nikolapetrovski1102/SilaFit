import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/core/widgets/mascot/ram_mascot.dart';
import 'package:silafit/core/widgets/mascot/talking_mascot.dart';
import 'package:silafit/features/onboarding/onboarding_controller.dart';
import 'package:silafit/features/onboarding/onboarding_mascot_lines.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  test('ram art resolves to one shared asset', () {
    expect(RamArt.smug.assetPath, 'assets/mascot/ram/smug.png');
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

  testWidgets('ram mascot uses the same art in either theme',
      (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(_host(const RamMascot(RamArt.smug, size: 40),
          brightness: brightness));
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName,
          'assets/mascot/ram/smug.png');
    }
  });

  testWidgets('talking mascot types its line and announces it whole',
      (tester) async {
    const line = MascotLine(RamArt.laughing, 'Hey there, champ!');
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(const TalkingMascot(line: line)));
    expect(find.bySemanticsLabel('Sila says: Hey there, champ!'),
        findsOneWidget);
    await tester.pumpAndSettle();
    final rich = tester.widget<Text>(find.byType(Text)).textSpan as TextSpan;
    expect((rich.children!.first as TextSpan).text, line.text);
    semantics.dispose();
  });

  testWidgets('talking mascot shows the full line at once with reduced motion',
      (tester) async {
    const line = MascotLine(RamArt.smug, 'No animations here.');
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: _host(const TalkingMascot(line: line)),
    ));
    final rich = tester.widget<Text>(find.byType(Text)).textSpan as TextSpan;
    expect((rich.children!.first as TextSpan).text, line.text);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/core/widgets/mascot/celebrating_ram.dart';
import 'package:silafit/core/widgets/mascot/confetti_burst.dart';
import 'package:silafit/core/widgets/mascot/mascot_dialog.dart';
import 'package:silafit/core/widgets/mascot/ram_mascot.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );

// Index into the IndexedStack: standing, charging, back.
int _pose(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

void main() {
  testWidgets('leaps, spins through the back view, then fist-pumps',
      (tester) async {
    var landed = 0;
    await tester.pumpWidget(_host(CelebratingRam(
      haptics: false,
      onLanded: () => landed++,
    )));
    expect(_pose(tester), 0);
    expect(find.byType(ConfettiBurst), findsNothing);

    // 220ms start delay, then the spin peaks around 25% of 2600ms.
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 650));
    expect(_pose(tester), 2, reason: 'facing away mid-spin');

    // Past the landing beat (40%).
    await tester.pump(const Duration(milliseconds: 500));
    expect(_pose(tester), 1, reason: 'fist pump after landing');
    expect(landed, 1);
    expect(find.byType(ConfettiBurst), findsOneWidget);

    // Settles back to standing.
    await tester.pump(const Duration(milliseconds: 1400));
    expect(_pose(tester), 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stands still with no confetti under reduced motion',
      (tester) async {
    await tester.pumpWidget(_host(
        const CelebratingRam(haptics: false),
        reduceMotion: true));
    await tester.pump(const Duration(seconds: 3));
    expect(_pose(tester), 0);
    expect(find.byType(ConfettiBurst), findsNothing);
  });

  testWidgets('celebration dialog stages Sila, plain dialog does not',
      (tester) async {
    await tester.pumpWidget(_host(const MascotDialog(
      pose: RamArt.charging,
      title: 'Workout complete',
      message: 'Nice work.',
      showConfetti: true,
    )));
    expect(find.byType(CelebratingRam), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_host(const MascotDialog(
      pose: RamArt.smug,
      title: 'Heads up',
      message: 'Just so you know.',
    )));
    expect(find.byType(CelebratingRam), findsNothing);
    expect(find.byType(RamMascot), findsOneWidget);
  });
}

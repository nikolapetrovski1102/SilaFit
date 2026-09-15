import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/core/widgets/container_transform.dart';
import 'package:silafit/core/widgets/hero_container_transform.dart';

void main() {
  for (final hero in [false, true]) {
    for (final physics in [
      const ClampingScrollPhysics(),
      const BouncingScrollPhysics(),
    ]) {
      testWidgets('swipe closes hero=$hero with $physics', (tester) async {
        Widget destination(BuildContext context) => Scaffold(
              appBar: AppBar(title: const Text('Details')),
              body: ListView(
                physics: physics,
                children: const [
                  SizedBox(height: 2000, child: Text('Content'))
                ],
              ),
            );
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Builder(builder: (context) {
            if (hero) {
              return TextButton(
                onPressed: () => Navigator.of(context)
                    .push(heroExpandRoute(builder: destination)),
                child: const Text('Open'),
              );
            }
            return ContainerTransform(
              closedBuilder: (context, open) =>
                  TextButton(onPressed: open, child: const Text('Open')),
              openBuilder: destination,
            );
          })),
        ));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        // A short pull must not dismiss.
        await tester.drag(find.byType(ListView), const Offset(0, 35));
        await tester.pumpAndSettle();
        expect(find.text('Details'), findsOneWidget);
        // Scrolling down into the content and back stays on the screen.
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 120));
        await tester.pumpAndSettle();
        expect(find.text('Details'), findsOneWidget);
        final scrollable =
            tester.state<ScrollableState>(find.byType(Scrollable));
        scrollable.position.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 180));
        await tester.pumpAndSettle();
        expect(find.text('Open'), findsOneWidget);
        expect(find.text('Details'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final reducedMotion in [false, true]) {
    testWidgets('opens and returns with reduced motion $reducedMotion',
        (tester) async {
      var closed = 0;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: ContainerTransform(
                  onClosed: () => closed++,
                  closedBuilder: (context, open) => TextButton(
                    onPressed: open,
                    child: const Text('Start Workout'),
                  ),
                  openBuilder: (context) => Scaffold(
                    appBar: AppBar(title: const Text('Workout')),
                    body: const Text('Session details'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Start Workout'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 225));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('Session details'), findsOneWidget);
      await tester.drag(find.text('Session details'), const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(find.text('Start Workout'), findsOneWidget);
      expect(closed, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

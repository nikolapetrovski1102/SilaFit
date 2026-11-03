import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/core/widgets/marker_drawn_title.dart';

Widget _host(String key) => MaterialApp(
    home: Scaffold(body: MarkerDrawnTitle('Settings', playKey: key)));

final _animating = find.descendant(
    of: find.byType(MarkerDrawnTitle), matching: find.byType(AnimatedBuilder));

void main() {
  setUp(MarkerDrawnTitle.resetPlayed);

  testWidgets('draws in the first time, then shows plain text', (tester) async {
    await tester.pumpWidget(_host('settings'));
    expect(_animating, findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    // Re-opening the page in the same session: no animation.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host('settings'));
    expect(_animating, findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('works under IntrinsicHeight', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                IntrinsicHeight(child: MarkerDrawnTitle('Hi', playKey: 'x')))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });
}

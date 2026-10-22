import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/core/widgets/swipe_action_tile.dart';

Widget _app(Widget tile, {SessionStore? store}) {
  final app = MaterialApp(
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: tile),
    ),
  );
  return store == null ? app : Provider.value(value: store, child: app);
}

SwipeActionTile _tile({
  required VoidCallback onDelete,
  bool showHint = false,
}) =>
    SwipeActionTile(
      showHint: showHint,
      actions: [
        SwipeAction(
          label: 'Duplicate',
          icon: Icons.copy_rounded,
          onTap: () {},
          disabledReason: 'Too many days.',
        ),
        SwipeAction(
          label: 'Delete',
          icon: Icons.delete_outline_rounded,
          isDestructive: true,
          onTap: onDelete,
        ),
      ],
      child: const SizedBox(height: 80, child: Text('Push day')),
    );

void main() {
  testWidgets('holding lifts the card into a menu that runs the action',
      (tester) async {
    var deleted = 0;
    await tester.pumpWidget(_app(_tile(onDelete: () => deleted++)));

    await tester.longPress(find.text('Push day'));
    await tester.pumpAndSettle();

    // The lifted copy is on screen and the reason for the disabled row shows.
    expect(find.text('Push day'), findsNWidgets(2));
    expect(find.text('Too many days.'), findsOneWidget);

    await tester.tap(find.text('Duplicate').last);
    await tester.pumpAndSettle();
    expect(find.text('Too many days.'), findsOneWidget,
        reason: 'disabled rows do nothing');

    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(deleted, 1);
    expect(find.text('Too many days.'), findsNothing);
    expect(find.text('Push day'), findsOneWidget);
  });

  testWidgets('swiping the lifted card closes the menu, a nudge does not',
      (tester) async {
    var deleted = 0;
    await tester.pumpWidget(_app(_tile(onDelete: () => deleted++)));
    await tester.longPress(find.text('Push day'));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Push day').last, const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(find.text('Too many days.'), findsOneWidget,
        reason: 'a short drag springs back');

    await tester.drag(find.text('Push day').last, const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.text('Too many days.'), findsNothing);
    expect(find.text('Push day'), findsOneWidget);
    expect(deleted, 0);
  });

  testWidgets('the peek hint plays once and stops after the user holds',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SessionStore();
    expect(store.shouldShowSwipeHint, isTrue);

    await tester
        .pumpWidget(_app(_tile(onDelete: () {}, showHint: true), store: store));
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 300));
    final card = find.text('Push day');
    expect(tester.getTopLeft(card).dx, lessThan(16),
        reason: 'the card slid open a little');
    // Past the pause it holds open, which schedules no frames.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(card).dx, 16, reason: 'and slid back');
    expect(store.shouldShowSwipeHint, isFalse, reason: 'once per launch');

    await tester.longPress(card);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('silen.swipe_actions_learned'), isTrue);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:silafit/features/progress/recap_animation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all six assets parse in both palettes, including AI gradients',
      () async {
    for (final brightness in Brightness.values) {
      for (final asset in [
        'confetti',
        'congratulations',
        'bar_graph',
        'heart_animated',
        'ai_stars',
        'sparks',
        'food',
      ]) {
        final composition = await loadRecapComposition(asset, brightness);
        expect(composition.duration, greaterThan(Duration.zero));
        expect(composition.layers, isNotEmpty);
      }
    }
  });

  testWidgets(
      'offscreen playback waits, completes once, and survives theme changes',
      (tester) async {
    await tester.runAsync(() async {
      for (final brightness in Brightness.values) {
        await loadRecapComposition('bar_graph', brightness);
      }
    });
    Future<void> show(bool active, Brightness brightness) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: TickerMode(
            enabled: active,
            child: const SizedBox(
                width: 152,
                height: 152,
                child: RecapAnimationStage(
                    child: RecapAnimation(asset: 'bar_graph')))),
      ));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    await show(false, Brightness.dark);
    final controller = tester.widget<Lottie>(find.byType(Lottie)).controller!;
    expect(controller.value, 0);
    await show(true, Brightness.dark);
    expect(controller.value, 1);
    await show(false, Brightness.dark);
    await show(true, Brightness.light);
    expect(tester.widget<Lottie>(find.byType(Lottie)).controller,
        same(controller));
    expect(controller.value, 1);
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      haptics.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.byType(RecapAnimationStage));
    await tester.pump();
    expect(controller.value, lessThan(1));
    expect(haptics.where((call) => call.method == 'HapticFeedback.vibrate'),
        hasLength(1));
    await tester.pumpAndSettle();
    expect(controller.value, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'food animation plays once, freezes at end, and survives theme changes',
      (tester) async {
    await tester.runAsync(() async {
      for (final brightness in Brightness.values) {
        await loadRecapComposition('food', brightness);
      }
    });
    Future<void> show(bool active, Brightness brightness) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: TickerMode(
            enabled: active,
            child: const SizedBox(
                width: 152,
                height: 152,
                child: RecapAnimationStage(
                    child: RecapAnimation(asset: 'food')))),
      ));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    await show(false, Brightness.dark);
    final controller = tester.widget<Lottie>(find.byType(Lottie)).controller!;
    expect(controller.value, 0);
    await show(true, Brightness.dark);
    expect(controller.value, 1);
    expect(controller.isCompleted, isTrue);
    await show(false, Brightness.dark);
    await show(true, Brightness.light);
    expect(tester.widget<Lottie>(find.byType(Lottie)).controller,
        same(controller));
    expect(controller.value, 1);
    expect(controller.isCompleted, isTrue);

    await tester.tap(find.byType(RecapAnimationStage));
    await tester.pump();
    expect(controller.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(controller.value, 1);
    expect(tester.takeException(), isNull);
  });
}

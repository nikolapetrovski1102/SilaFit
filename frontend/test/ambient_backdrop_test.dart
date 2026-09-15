import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/core/theme/app_colors.dart';
import 'package:silafit/root_shell.dart';

void main() {
  testWidgets('ambient backdrop repaints with the active theme',
      (tester) async {
    final mode = ValueNotifier(ThemeMode.dark);
    addTearDown(mode.dispose);

    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (context, value, child) => MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: value,
          home: const SilenAmbientBackdrop(),
        ),
      ),
    );

    expect(_glowColors(tester),
        everyElement(AppPalette.dark.accent.withOpacity(0.28)));
    expect(
      tester.widget<RepaintBoundary>(find.byType(RepaintBoundary)).key,
      ValueKey(AppPalette.dark.accent),
    );

    mode.value = ThemeMode.light;
    await tester.pump();

    expect(_glowColors(tester),
        everyElement(AppPalette.light.accent.withOpacity(0.28)));
    expect(
      tester.widget<RepaintBoundary>(find.byType(RepaintBoundary)).key,
      ValueKey(AppPalette.light.accent),
    );
  });
}

Iterable<Color?> _glowColors(WidgetTester tester) {
  return tester
      .widgetList<Container>(find.byType(Container))
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .where((decoration) => decoration.shape == BoxShape.circle)
      .map((decoration) => decoration.color);
}

// Minimal smoke test: the app boots without throwing. Replaces the default
// counter-app template test, which referenced a `MyApp` class that doesn't
// exist in this project.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:silafit/main.dart';

void main() {
  testWidgets('SilenApp builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const SilenApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

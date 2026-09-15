import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:silafit/core/widgets/fit_height.dart';

void main() {
  testWidgets('measurement copy does not register duplicate heroes',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FitHeight(
              availableHeight: 200,
              builder: (_) => Hero(
                tag: 'fit-height-hero',
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: Hero(
                          tag: 'fit-height-hero',
                          child: SizedBox(width: 100, height: 100),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

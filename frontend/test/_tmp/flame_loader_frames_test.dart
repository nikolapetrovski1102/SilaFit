import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/core/widgets/mascot/flame_loader.dart';

void main() {
  testWidgets('frames', (tester) async {
    tester.view.physicalSize = const Size(300, 300);
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: RepaintBoundary(key: key, child: const ColoredBox(color: Color(0xFF172D30), child: Center(child: FlameLoader(size: 260)))),
    ));
    for (final n in ['back','base','flicker_a','flicker_b','blink']) {
      await tester.runAsync(() => precacheImage(AssetImage('assets/mascot/flame/dark/loader_$n.png'), key.currentContext!));
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump(Duration(milliseconds: i == 0 ? 0 : 517));
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await boundary.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('/private/tmp/claude-501/-Users-nikolapetrovski-Developer-Silen/7bb9ddfb-6338-4cbb-b4fb-ba303dc50c19/scratchpad/loader/frame_$i.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}

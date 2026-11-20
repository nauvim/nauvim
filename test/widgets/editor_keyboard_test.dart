import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nauvim_flutter/nauvim.dart';
import 'package:nauvim_flutter/nauvim_material.dart';

import '../support/fakes.dart';

void main() {
  for (final platform in [TargetPlatform.linux, TargetPlatform.macOS]) {
    testWidgets('forwards Ctrl Shift T to Neovim on ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final engine = FakeEngine();
      final controller = NauvimController(
        engine: engine,
        platform: FakePlatform(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await engine.events.close();
        debugDefaultTargetPlatformOverride = null;
      });
      await tester.pumpWidget(NauvimMaterialApp(controller: controller));
      engine.emit(const UiUpdate(kind: 'ready', hosts: [], fonts: []));
      await tester.pump();
      await tester.pump();
      engine.emit(
        const UiUpdate(
          kind: 'frame',
          hosts: [],
          fonts: [],
          frame: DisplayFrame(
            full: true,
            grids: [],
            removedGrids: [],
            rows: [],
            highlights: [],
            foreground: 0xffffff,
            background: 0x15181e,
            title: '',
            mode: 'normal',
            busy: false,
            widgets: [],
            events: [],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(engine.inputs, ['<S-C-t>', '<S-C-t>']);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(engine.inputs, ['<S-C-t>', '<S-C-t>', '<C-t>']);
      expect(tester.takeException(), isNull);
    });
  }
}

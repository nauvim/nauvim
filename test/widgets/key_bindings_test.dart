import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nauvim_flutter/nauvim.dart';
import 'package:nauvim_flutter/nauvim_material.dart';
import 'package:nauvim_flutter/nauvim_widgets.dart' show boundKey;

import '../support/fakes.dart';

Future<
  ({FakeEngine engine, FakePlatform platform, NauvimController controller})
>
editor(
  WidgetTester tester,
  TargetPlatform target, {
  KeyBindings? bindings,
}) async {
  debugDefaultTargetPlatformOverride = target;
  final engine = FakeEngine();
  final platform = FakePlatform();
  final controller = NauvimController(engine: engine, platform: platform);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await engine.events.close();
    debugDefaultTargetPlatformOverride = null;
  });
  await tester.pumpWidget(NauvimMaterialApp(controller: controller));
  engine.emit(
    UiUpdate(
      kind: 'ready',
      hosts: const [],
      fonts: const [],
      keyBindings: bindings,
    ),
  );
  await tester.pump();
  await tester.pump();
  engine.emit(
    const UiUpdate(
      kind: 'frame',
      hosts: [],
      fonts: [],
      frame: DisplayFrame(
        full: true,
        grids: [
          DisplayGrid(
            id: 1,
            width: 2,
            height: 1,
            row: 0,
            col: 0,
            zindex: 0,
            order: 0,
            hidden: false,
          ),
        ],
        rows: [
          DisplayRow(
            grid: 1,
            row: 0,
            cells: [
              DisplayCell(text: 'a', highlight: 0),
              DisplayCell(text: 'b', highlight: 0),
            ],
          ),
        ],
        removedGrids: [],
        highlights: [],
        title: '',
        mode: 'normal',
        busy: false,
        events: [],
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (engine: engine, platform: platform, controller: controller);
}

Future<void> chord(
  WidgetTester tester,
  LogicalKeyboardKey key,
  List<LogicalKeyboardKey> modifiers,
) async {
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyEvent(key);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
}

void select(NauvimController controller) {
  controller.editor.beginSelection(const CellPoint(1, 0, 0));
  controller.editor.extendSelection(const CellPoint(1, 0, 1));
}

void main() {
  test('retains modified Enter and Escape defaults as explicit chords', () {
    final defaults = NauvimKeyBindings();
    for (var modifiers = 0; modifiers < 16; modifiers++) {
      expect(
        defaults.lookup(KeyContext.welcome, 'enter', modifiers),
        KeyAction.activate,
      );
      expect(
        defaults.lookup(KeyContext.welcome, 'numpadenter', modifiers),
        KeyAction.activate,
      );
      expect(
        defaults.lookup(KeyContext.welcome, 'escape', modifiers),
        KeyAction.back,
      );
    }
    final configured = NauvimKeyBindings(
      const KeyBindings(
        welcome: [
          KeyBinding(key: 'enter', modifiers: 1, action: KeyAction.quit),
        ],
        clipboard: [],
        webview: [],
      ),
    );
    expect(configured.lookup(KeyContext.welcome, 'enter', 1), KeyAction.quit);
    expect(
      configured.lookup(KeyContext.welcome, 'enter', 0),
      KeyAction.activate,
    );
  });

  testWidgets('matches shifted digit identities, symbols, and Unicode labels', (
    tester,
  ) async {
    final bindings = NauvimKeyBindings(
      const KeyBindings(
        welcome: [
          KeyBinding(key: '1', modifiers: 2, action: KeyAction.selectNext),
          KeyBinding(key: '+', modifiers: 2, action: KeyAction.activate),
          KeyBinding(key: 'É', modifiers: 0, action: KeyAction.back),
        ],
        clipboard: [],
        webview: [],
      ),
    );
    KeyAction? resolve(LogicalKeyboardKey logical, String character) =>
        boundKey(
          bindings,
          KeyContext.welcome,
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.digit1,
            logicalKey: logical,
            character: character,
            timeStamp: Duration.zero,
          ),
        );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(resolve(LogicalKeyboardKey.digit1, '!'), KeyAction.selectNext);
    expect(resolve(LogicalKeyboardKey.add, '+'), KeyAction.activate);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(resolve(const LogicalKeyboardKey(0xe9), 'é'), KeyAction.back);
    expect(resolve(LogicalKeyboardKey.digit1, '1'), isNull);
  });

  for (final target in [TargetPlatform.linux, TargetPlatform.macOS]) {
    testWidgets('keeps default clipboard shortcuts on ${target.name}', (
      tester,
    ) async {
      final (:engine, :platform, :controller) = await editor(tester, target);
      final modifiers = target == TargetPlatform.macOS
          ? [LogicalKeyboardKey.metaLeft]
          : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];
      select(controller);
      await chord(tester, LogicalKeyboardKey.keyC, modifiers);
      expect(platform.clipboard, ['ab']);
      await chord(tester, LogicalKeyboardKey.keyV, modifiers);
      expect(engine.pastes, 1);
      expect(engine.inputs, isEmpty);
    });
  }

  testWidgets(
    'remaps clipboard commands with exact modifiers and forwards unbound chords',
    (tester) async {
      final (:engine, :platform, :controller) = await editor(
        tester,
        TargetPlatform.linux,
        bindings: const KeyBindings(
          welcome: [],
          webview: [],
          clipboard: [
            KeyBinding(key: 'c', modifiers: 3),
            KeyBinding(key: 'v', modifiers: 3),
            KeyBinding(key: 'y', modifiers: 4, action: KeyAction.copy),
            KeyBinding(key: 'p', modifiers: 4, action: KeyAction.paste),
          ],
        ),
      );
      select(controller);
      await chord(tester, LogicalKeyboardKey.keyC, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ]);
      expect(platform.clipboard, isEmpty);
      expect(engine.inputs.last, '<S-C-c>');
      select(controller);
      await chord(tester, LogicalKeyboardKey.keyY, [
        LogicalKeyboardKey.altLeft,
      ]);
      expect(platform.clipboard, ['ab']);
      await chord(tester, LogicalKeyboardKey.keyP, [
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.shiftLeft,
      ]);
      expect(engine.pastes, 0);
      await chord(tester, LogicalKeyboardKey.keyP, [
        LogicalKeyboardKey.altLeft,
      ]);
      expect(engine.pastes, 1);
      await chord(tester, LogicalKeyboardKey.keyV, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ]);
      expect(engine.pastes, 1);
      expect(engine.inputs.last, '<S-C-v>');
      controller.editor.clearSelection();
      await chord(tester, LogicalKeyboardKey.keyY, [
        LogicalKeyboardKey.altLeft,
      ]);
      expect(engine.inputs.last, '<M-y>');
    },
  );
}

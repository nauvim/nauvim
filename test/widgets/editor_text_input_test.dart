import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nauvim_flutter/nauvim.dart';
import 'package:nauvim_flutter/nauvim_material.dart';
import 'package:nauvim_flutter/nauvim_widgets.dart';

import '../support/fakes.dart';

const _frame = DisplayFrame(
  full: true,
  grids: [
    DisplayGrid(
      id: 1,
      width: 30,
      height: 10,
      row: 0,
      col: 0,
      zindex: 0,
      order: 0,
      hidden: false,
    ),
  ],
  removedGrids: [],
  rows: [],
  highlights: [],
  foreground: 0xffffff,
  background: 0x15181e,
  cursor: DisplayCursor(
    grid: 1,
    row: 1,
    col: 2,
    shape: 'block',
    percentage: 100,
  ),
  title: '',
  mode: 'insert',
  busy: false,
  widgets: [],
  events: [],
);

Finder _preedit(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter is EditorPainter &&
      (widget.painter as EditorPainter).preedit?.text == text,
);

Future<(NauvimController, FakeEngine)> _attach(WidgetTester tester) async {
  final engine = FakeEngine();
  final controller = NauvimController(engine: engine, platform: FakePlatform());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await engine.events.close();
  });

  await tester.pumpWidget(NauvimMaterialApp(controller: controller));
  engine.emit(const UiUpdate(kind: 'ready', hosts: [], fonts: []));
  await tester.pumpAndSettle();
  engine.emit(
    const UiUpdate(kind: 'frame', hosts: [], fonts: [], frame: _frame),
  );
  await tester.pumpAndSettle();
  return (controller, engine);
}

void main() {
  testWidgets('composes in Flutter and forwards each literal commit once', (
    tester,
  ) async {
    final (controller, engine) = await _attach(tester);
    final start = find.widgetWithIcon(IconButton, Icons.keyboard_outlined);
    final stop = find.widgetWithIcon(IconButton, Icons.keyboard);
    final input = tester.testTextInput;
    expect(input.hasAnyClients, isFalse);

    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(controller.nativeTextInput, isTrue);
    expect(input.hasAnyClients, isTrue);

    // The framework defers the key to native text input. A widget test sends
    // editing states explicitly instead of relying on a platform IME.
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse);
    const text = '日本😀<Esc>';
    input.updateEditingValue(
      const TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: TextRange(start: 0, end: text.length),
      ),
    );
    await tester.pumpAndSettle();
    expect(_preedit(text), findsOneWidget);
    expect(engine.inputs, isEmpty);
    final methods = input.log.map((call) => call.method);
    expect(methods, contains('TextInput.setMarkedTextRect'));
    expect(methods, contains('TextInput.setCaretRect'));

    const committed = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    input.updateEditingValue(committed);
    input.updateEditingValue(committed);
    await tester.pumpAndSettle();
    expect(_preedit(text), findsNothing);
    expect(engine.inputs, ['日本😀<LT>Esc>']);

    input.updateEditingValue(
      const TextEditingValue(
        text: '$text候',
        selection: TextSelection.collapsed(offset: text.length + 1),
        composing: TextRange(start: text.length, end: text.length + 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(_preedit('候'), findsOneWidget);
    input.updateEditingValue(committed);
    await tester.pumpAndSettle();
    expect(_preedit('候'), findsNothing);
    expect(engine.inputs, ['日本😀<LT>Esc>']);

    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(controller.nativeTextInput, isFalse);
    expect(input.hasAnyClients, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(engine.inputs, ['日本😀<LT>Esc>', '<Esc>']);
  });

  testWidgets('drops pending composition and closes the client on detachment', (
    tester,
  ) async {
    final (controller, engine) = await _attach(tester);
    controller.setNativeTextInput(true);
    await tester.pumpAndSettle();

    final input = tester.testTextInput;
    input.updateEditingValue(
      const TextEditingValue(
        text: '仮',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(_preedit('仮'), findsOneWidget);

    engine.emit(const UiUpdate(kind: 'welcome', hosts: [], fonts: []));
    await tester.pumpAndSettle();
    expect(controller.nativeTextInput, isFalse);
    expect(input.hasAnyClients, isFalse);
    expect(_preedit('仮'), findsNothing);
    expect(engine.inputs, isEmpty);
  });
}

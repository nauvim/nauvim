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
  mode: 'normal',
  busy: false,
  widgets: [],
  events: [],
);

const _attached = UiUpdate(kind: 'frame', hosts: [], fonts: [], frame: _frame);

class _TextInputPlatform extends FakePlatform
    implements EditorTextInputPlatform {
  final opened = <int, void Function(EditorTextInputEvent)>{};
  final closed = <int>[];
  final geometry = <(int, Rect, Rect)>[];

  @override
  Future<void> openTextInput(
    int client,
    void Function(EditorTextInputEvent) onEdit,
  ) async => opened[client] = onEdit;

  @override
  Future<void> closeTextInput(int client) async => closed.add(client);

  @override
  Future<void> updateTextInputGeometry(
    int client, {
    required Rect caret,
    required Rect composing,
  }) async => geometry.add((client, caret, composing));
}

Finder _preedit(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter is EditorPainter &&
      (widget.painter as EditorPainter).preedit?.text == text,
);

Future<(NauvimController, FakeEngine, _TextInputPlatform)> _attach(
  WidgetTester tester, {
  bool? ime,
}) async {
  final engine = FakeEngine();
  final platform = _TextInputPlatform();
  final controller = NauvimController(engine: engine, platform: platform);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await engine.events.close();
  });

  await tester.pumpWidget(NauvimMaterialApp(controller: controller));
  engine.emit(
    UiUpdate(kind: 'ready', hosts: const [], fonts: const [], ime: ime),
  );
  await tester.pumpAndSettle();
  engine.emit(_attached);
  await tester.pumpAndSettle();
  return (controller, engine, platform);
}

void main() {
  testWidgets(
    'preedits in normal mode and orders literal commits with returned keys',
    (tester) async {
      final (controller, engine, platform) = await _attach(tester);
      expect(controller.nativeTextInput, isTrue);
      final client = platform.opened.keys.single;
      final edit = platform.opened[client]!;
      expect(platform.geometry.last.$1, client);
      expect(platform.geometry.last.$2.isEmpty, isFalse);

      const text = '日本😀<Esc>';
      edit(
        const EditorPreedit(
          text: text,
          selectionStart: 0,
          selectionEnd: 2,
          segments: [(start: 0, end: 2, selected: true)],
        ),
      );
      await tester.pumpAndSettle();
      expect(_preedit(text), findsOneWidget);
      expect(
        platform.geometry.last.$3.width,
        greaterThan(platform.geometry.last.$2.width),
      );
      expect(engine.inputs, isEmpty);

      edit(const EditorTextCommit(text));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      edit(const EditorTextCommit('次'));
      await tester.pumpAndSettle();
      expect(_preedit(text), findsNothing);
      expect(engine.inputs, ['日本😀<LT>Esc>', '<Esc>', '次']);

      edit(const EditorPreedit(text: '仮', selectionStart: 1, selectionEnd: 1));
      await tester.pumpAndSettle();
      expect(_preedit('仮'), findsOneWidget);
      edit(const EditorPreedit(text: '', selectionStart: 0, selectionEnd: 0));
      await tester.pumpAndSettle();
      expect(_preedit('仮'), findsNothing);
      expect(engine.inputs, ['日本😀<LT>Esc>', '<Esc>', '次']);
    },
  );

  testWidgets(
    'clears preedit on detach and drops stale edits after reattachment',
    (tester) async {
      final (_, engine, platform) = await _attach(tester);
      final client = platform.opened.keys.single;
      final edit = platform.opened[client]!;
      const draft = EditorPreedit(
        text: '仮',
        selectionStart: 1,
        selectionEnd: 1,
      );
      edit(draft);
      await tester.pumpAndSettle();
      expect(_preedit('仮'), findsOneWidget);

      engine.emit(const UiUpdate(kind: 'welcome', hosts: [], fonts: []));
      await tester.pumpAndSettle();
      expect(platform.closed, [client]);
      expect(_preedit('仮'), findsNothing);

      engine.emit(_attached);
      await tester.pumpAndSettle();
      final next = platform.opened.keys.last;
      expect(next, isNot(client));
      edit(draft);
      edit(const EditorTextCommit('stale'));
      platform.opened[next]!(const EditorTextCommit('current'));
      await tester.pumpAndSettle();
      expect(_preedit('仮'), findsNothing);
      expect(engine.inputs, ['current']);
    },
  );

  testWidgets('clears preedit when the attached editor loses focus', (
    tester,
  ) async {
    final (_, engine, platform) = await _attach(tester);
    final client = platform.opened.keys.single;
    final edit = platform.opened[client]!;
    const draft = EditorPreedit(text: '仮', selectionStart: 1, selectionEnd: 1);
    edit(draft);
    await tester.pumpAndSettle();
    expect(_preedit('仮'), findsOneWidget);

    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    expect(platform.closed, [client]);
    expect(_preedit('仮'), findsNothing);

    edit(draft);
    edit(const EditorTextCommit('already committed'));
    await tester.pumpAndSettle();
    expect(_preedit('仮'), findsNothing);
    expect(engine.inputs, ['already committed']);
  });

  testWidgets('keeps ordinary input when ime is false', (tester) async {
    final (controller, engine, platform) = await _attach(tester, ime: false);
    expect(controller.nativeTextInput, isFalse);
    expect(platform.opened, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(engine.inputs, ['<Esc>']);
  });
}

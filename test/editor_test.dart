import 'package:nauvim_flutter/nauvim_widgets.dart';

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nauvim_flutter/main.dart';
import 'package:nauvim_flutter/nauvim.dart';
import 'package:nauvim_flutter/nauvim_material.dart';

import 'support/fakes.dart';

import 'package:material_ui/material_ui.dart';

DisplayGrid grid(int id, {double col = 0}) => DisplayGrid(
  id: id,
  width: 3,
  height: 1,
  row: 0,
  col: col,
  zindex: id,
  order: id,
  hidden: false,
);
DisplayFrame frame({
  List<DisplayRow> rows = const [],
  List<DisplayGrid>? grids,
  List<DisplayHighlight> highlights = const [],
}) => DisplayFrame(
  full: false,
  grids: grids ?? [grid(1), grid(2, col: 4)],
  removedGrids: const [],
  rows: rows,
  highlights: highlights,
  foreground: 0xffffff,
  background: 0x15181e,
  title: '',
  mode: 'normal',
  busy: false,
  widgets: const [],
  events: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('maps byte offsets at scalar boundaries to Flutter positions', () {
    const text = ':a界😀e\u0301';
    for (final (bytes, units) in [
      (-1, 0),
      (0, 0),
      (1, 1),
      (2, 2),
      (3, 2),
      (4, 2),
      (5, 3),
      (8, 3),
      (9, 5),
      (10, 6),
      (12, 7),
      (100, 7),
    ]) {
      expect(
        byteOffsetToUtf16(text, bytes),
        units,
        reason: 'byte offset $bytes',
      );
    }
  });
  test(
    'retains row revisions when moving a grid and replaces resized content',
    () {
      final model = EditorModel();
      model.apply(
        frame(
          rows: [
            const DisplayRow(
              grid: 1,
              row: 0,
              cells: [DisplayCell(text: 'old', highlight: 0)],
            ),
          ],
        ),
      );
      final generation = model.generation;
      final row = model.grids[1]!.rows[0];
      final revision = model.grids[1]!.revisions[0]!;
      model.apply(frame(grids: [grid(1, col: 2), grid(2, col: 4)]));
      expect(model.generation, generation);
      expect(identical(model.grids[1]!.rows[0], row), isTrue);
      expect(model.grids[1]!.revisions[0], revision);
      model.apply(
        frame(
          grids: [
            const DisplayGrid(
              id: 1,
              width: 4,
              height: 1,
              row: 0,
              col: 0,
              zindex: 1,
              order: 1,
              hidden: false,
            ),
          ],
          rows: [
            const DisplayRow(
              grid: 1,
              row: 0,
              cells: [DisplayCell(text: 'new', highlight: 0)],
            ),
          ],
        ),
      );
      expect(model.grids[1]!.revisions[0], greaterThan(revision));
      expect(model.grids[1]!.rows[0]!.first.text, 'new');
      model.dispose();
    },
  );
  test('uses composition order for overlapping grids at the same z-index', () {
    final model = EditorModel();
    model.apply(
      frame(
        grids: [
          const DisplayGrid(
            id: 1,
            width: 3,
            height: 1,
            row: 0,
            col: 0,
            zindex: 10,
            order: 9,
            hidden: false,
          ),
          const DisplayGrid(
            id: 2,
            width: 3,
            height: 1,
            row: 0,
            col: 0,
            zindex: 10,
            order: 3,
            hidden: false,
          ),
        ],
      ),
    );
    expect(model.visibleGrids.map((grid) => grid.geometry.id), [2, 1]);
    expect(model.hit(1, 1, 10, 20)?.grid, 1);
    model.dispose();
  });
  test('retains unchanged rows and confines selections to their grid', () {
    final model = EditorModel();
    model.apply(
      frame(
        rows: [
          const DisplayRow(
            grid: 1,
            row: 0,
            cells: [
              DisplayCell(text: '界', highlight: 0),
              DisplayCell(text: '', highlight: 0),
              DisplayCell(text: 'a', highlight: 0),
            ],
          ),
          const DisplayRow(
            grid: 2,
            row: 0,
            cells: [DisplayCell(text: 'z', highlight: 0)],
          ),
        ],
      ),
    );
    final retained = model.grids[1]!.rows[0];
    model.apply(frame());
    expect(identical(model.grids[1]!.rows[0], retained), isTrue);
    model.beginSelection(const CellPoint(1, 0, 0));
    model.extendSelection(const CellPoint(2, 0, 0));
    expect(model.selectedText(), '界');
    model.extendSelection(const CellPoint(1, 0, 2));
    expect(model.selectedText(), '界a');
    expect(model.selectedColumns(1, 0), (0, 3));
    expect(model.selectedColumns(2, 0), isNull);
    expect(model.selectedColumns(1, 1), isNull);
    expect(model.hit(41, 1, 10, 20)?.grid, 2);
    model.apply(frame(grids: [grid(2)]));
    expect(model.selectionStart, isNull);
    model.dispose();
  });
  test('escapes literal less-than and emits explicit special-key notation', () {
    expect(
      encodeKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.comma,
          logicalKey: LogicalKeyboardKey.comma,
          character: '<',
          timeStamp: Duration.zero,
        ),
      ),
      '<LT>',
    );
    expect(
      encodeKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      ),
      '<CR>',
    );
    expect(
      encodeKey(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      ),
      isNull,
    );
  });
  testWidgets(
    'command line uses shaped Unicode offsets and paints its cursor',
    (tester) async {
      final model = EditorModel();
      final item = DisplayWidget(
        kind: 'cmdline',
        grid: 1,
        row: 0,
        col: 0,
        selected: 9,
        chunks: const [DisplayChunk(text: ':a界😀', highlight: 0)],
        items: const [],
        handles: const [],
      );
      const style = TextStyle(fontFamily: 'monospace', fontSize: 16);
      final expected = widgetTextPainter(item, model, style);
      final caret = expected.getOffsetForCaret(
        const TextPosition(offset: 5),
        Rect.zero,
      );
      expect(commandLineOffset(item, model, style, 9), caret.dx);
      expected.dispose();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CommandLine(
            item: item,
            model: model,
            style: style,
            active: true,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  testWidgets(
    'follows a long command-line cursor and its scrolled popup anchor',
    (tester) async {
      final model = EditorModel();
      final link = LayerLink();
      final text = ':${List.filled(100, '界').join()}';
      final viewportKey = GlobalKey();
      Widget line(int cursor) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: viewportKey,
            width: 140,
            height: 30,
            child: CommandLine(
              item: DisplayWidget(
                kind: 'cmdline',
                grid: 1,
                row: 0,
                col: 0,
                selected: cursor,
                chunks: [DisplayChunk(text: text, highlight: 0)],
                items: const [],
                handles: const [],
              ),
              model: model,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
              active: true,
              popupLink: link,
              popupByteOffset: cursor,
              popupWidth: 100,
            ),
          ),
        ),
      );
      await tester.pumpWidget(line(301));
      await tester.pump();
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.pixels, greaterThan(0));
      final viewport = tester.getRect(find.byKey(viewportKey));
      var anchor = tester.getTopLeft(find.byType(CompositedTransformTarget));
      expect(anchor.dx, inInclusiveRange(viewport.left, viewport.right - 100));
      await tester.pumpWidget(line(0));
      await tester.pump();
      expect(scrollable.position.pixels, 0);
      anchor = tester.getTopLeft(find.byType(CompositedTransformTarget));
      expect(anchor.dx, viewport.left);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
  testWidgets(
    'welcome displays configuration failures without closing the application',
    (tester) async {
      await tester.pumpWidget(
        const NauvimApp(startupError: 'Cannot read config.lua'),
      );
      expect(find.text('Your Neovim, anywhere.'), findsOneWidget);
      expect(find.text('Cannot read config.lua'), findsOneWidget);
      expect(find.text('Type yourself'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'client diagnostics remain visible after attachment until dismissed',
    (tester) async {
      final engine = FakeEngine();
      final controller = NauvimController(
        engine: engine,
        platform: FakePlatform(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await engine.events.close();
      });
      await tester.pumpWidget(NauvimMaterialApp(controller: controller));
      engine.emit(
        const UiUpdate(
          kind: 'error',
          message: 'Clipboard backend is unavailable',
          hosts: [],
          fonts: [],
        ),
      );
      engine.emit(
        UiUpdate(
          kind: 'frame',
          frame: frame(),
          hosts: const [],
          fonts: const [],
        ),
      );
      await tester.pump();
      expect(find.text('Clipboard backend is unavailable'), findsOneWidget);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
      await tester.pump();
      expect(find.text('Clipboard backend is unavailable'), findsNothing);
    },
  );
  testWidgets(
    'confines grid painting to its translated viewport and restores the canvas',
    (tester) async {
      final model = EditorModel()..apply(frame(grids: [grid(1)]));
      final renderer = GridRenderer();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(const Color(0xffffffff), BlendMode.src);
      canvas.save();
      canvas.translate(30, 30);
      renderer.paint(
        canvas,
        const Size(20, 20),
        model,
        'monospace',
        const [],
        14,
        10,
        20,
      );
      canvas.drawRect(
        const Rect.fromLTWH(40, 40, 5, 5),
        Paint()..color = const Color(0xff00ff00),
      );
      canvas.restore();
      final picture = recorder.endRecording();
      final image = await tester.runAsync(() => picture.toImage(100, 100));
      final data = await tester.runAsync(() => image!.toByteData());
      List<int> pixel(int x, int y) {
        final offset = (y * 100 + x) * 4;
        return [for (var i = 0; i < 4; i++) data!.getUint8(offset + i)];
      }

      for (final (x, y) in [(0, 0), (29, 35), (50, 35), (35, 29), (35, 50)]) {
        expect(pixel(x, y), [
          255,
          255,
          255,
          255,
        ], reason: 'outside viewport at ($x,$y)');
      }
      expect(pixel(35, 35), [0x15, 0x18, 0x1e, 255]);
      expect(pixel(72, 72), [0, 255, 0, 255]);
      image!.dispose();
      picture.dispose();
      renderer.dispose();
      model.dispose();
    },
  );
  testWidgets(
    'repaints resized rows and changed cell metrics from retained caches',
    (tester) async {
      final model = EditorModel();
      final renderer = GridRenderer();
      DisplayHighlight highlight(int id, int background) => DisplayHighlight(
        id: id,
        background: background,
        reverse: false,
        bold: false,
        italic: false,
        underline: false,
        undercurl: false,
        decoration: '',
        strikethrough: false,
        blend: 0,
      );
      Future<List<int>> pixel(double cellWidth, int x) async {
        final recorder = ui.PictureRecorder();
        renderer.paint(
          Canvas(recorder),
          const Size(80, 20),
          model,
          'monospace',
          const [],
          14,
          cellWidth,
          20,
        );
        final picture = recorder.endRecording();
        final image = await tester.runAsync(() => picture.toImage(80, 20));
        final data = await tester.runAsync(() => image!.toByteData());
        final offset = (10 * 80 + x) * 4;
        final rgba = [for (var i = 0; i < 4; i++) data!.getUint8(offset + i)];
        image!.dispose();
        picture.dispose();
        return rgba;
      }

      model.apply(
        frame(
          grids: [grid(1)],
          highlights: [highlight(1, 0xff0000), highlight(2, 0x0000ff)],
          rows: [
            const DisplayRow(
              grid: 1,
              row: 0,
              cells: [DisplayCell(text: ' ', highlight: 1)],
            ),
          ],
        ),
      );
      expect(await pixel(10, 5), [255, 0, 0, 255]);
      model.apply(
        frame(
          grids: [
            const DisplayGrid(
              id: 1,
              width: 4,
              height: 1,
              row: 0,
              col: 0,
              zindex: 1,
              order: 1,
              hidden: false,
            ),
          ],
          rows: [
            const DisplayRow(
              grid: 1,
              row: 0,
              cells: [DisplayCell(text: ' ', highlight: 2)],
            ),
          ],
        ),
      );
      expect(await pixel(10, 5), [0, 0, 255, 255]);
      expect(await pixel(20, 15), [0, 0, 255, 255]);
      renderer.dispose();
      model.dispose();
    },
  );
  testWidgets(
    'renders wide cells, a floating grid, and selection without overflow',
    (tester) async {
      final model = EditorModel();
      final renderer = GridRenderer();
      model.apply(
        frame(
          rows: [
            const DisplayRow(
              grid: 1,
              row: 0,
              cells: [
                DisplayCell(text: '界', highlight: 0),
                DisplayCell(text: '', highlight: 0),
                DisplayCell(text: 'a', highlight: 0),
              ],
            ),
            const DisplayRow(
              grid: 2,
              row: 0,
              cells: [DisplayCell(text: 'z', highlight: 0)],
            ),
          ],
        ),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 100,
                height: 30,
                child: CustomPaint(
                  painter: EditorPainter(
                    model,
                    renderer,
                    'monospace',
                    const [],
                    16,
                    10,
                    20,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      expect(image.width, 100);
      expect(image.height, 30);
      image.dispose();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      renderer.dispose();
      model.dispose();
    },
  );
}

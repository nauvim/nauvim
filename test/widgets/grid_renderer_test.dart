import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nauvim_flutter/nauvim.dart';
import 'package:nauvim_flutter/nauvim_widgets.dart';
import 'package:nauvim_flutter/src/widgets/grid_preedit.dart';

DisplayHighlight background(int id) => DisplayHighlight(
  id: id,
  background: 0xee5599,
  reverse: false,
  bold: false,
  italic: false,
  underline: false,
  undercurl: false,
  decoration: '',
  strikethrough: false,
  blend: 0,
);

EditorModel model(
  List<DisplayCell> cells, {
  List<DisplayHighlight> highlights = const [],
  DisplayCursor? cursor,
}) => EditorModel()
  ..apply(
    DisplayFrame(
      full: true,
      grids: [
        DisplayGrid(
          id: 1,
          width: cells.length,
          height: 1,
          row: 0,
          col: 0,
          zindex: 0,
          order: 0,
          hidden: false,
        ),
      ],
      removedGrids: const [],
      rows: [DisplayRow(grid: 1, row: 0, cells: cells)],
      highlights: highlights,
      foreground: 0xffffff,
      background: 0x000000,
      cursor: cursor,
      title: '',
      mode: 'normal',
      busy: false,
      widgets: const [],
      events: const [],
    ),
  );

Future<ByteData> raster(
  WidgetTester tester,
  EditorModel model,
  GridRenderer renderer, {
  required int width,
  double cellWidth = 20,
  double fontSize = 20,
  Offset offset = Offset.zero,
  EditorFont? fonts,
  double? baseline,
  GridPreedit? preedit,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..translate(offset.dx, offset.dy);
  renderer.paint(
    canvas,
    Size(width.toDouble(), 20),
    model,
    'NauvimGridTest',
    const [],
    fontSize,
    cellWidth,
    20,
    fonts: fonts,
    baseline: baseline,
    preedit: preedit,
  );
  final picture = recorder.endRecording();
  final image = await tester.runAsync(() => picture.toImage(width, 22));
  final data = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  image!.dispose();
  picture.dispose();
  return data!;
}

List<int> pixel(ByteData data, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return [
    for (var channel = 0; channel < 4; channel++)
      data.getUint8(offset + channel),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = await File('test/fixtures/grid_test.ttf').readAsBytes();
    final loader = FontLoader('NauvimGridTest')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  testWidgets(
    'joins Powerline semicircles to the full cell height at every font size',
    (tester) async {
      final editor = model(
        const [
          DisplayCell(text: '\ue0b6', highlight: 1),
          DisplayCell(text: ' ', highlight: 2),
          DisplayCell(text: '\ue0b4', highlight: 1),
        ],
        highlights: [
          const DisplayHighlight(
            id: 1,
            foreground: 0xee5599,
            background: 0,
            reverse: false,
            bold: false,
            italic: false,
            underline: false,
            undercurl: false,
            decoration: '',
            strikethrough: false,
            blend: 0,
          ),
          background(2),
        ],
      );
      final renderer = GridRenderer();
      addTearDown(() {
        renderer.dispose();
        editor.dispose();
      });
      for (final fontSize in [10.0, 20.0, 30.0]) {
        final data = await raster(
          tester,
          editor,
          renderer,
          width: 60,
          fontSize: fontSize,
        );
        for (var y = 0; y < 20; y++) {
          for (final x in [19, 20, 39, 40]) {
            final actual = pixel(data, 60, x, y);
            if ((y == 0 || y == 19) && (x == 19 || x == 40)) {
              // Only the curved boundary's endpoint may be antialiased.
              for (final (index, expected) in [0xee, 0x55, 0x99].indexed) {
                expect(actual[index], closeTo(expected, 6));
              }
              expect(actual[3], 255);
            } else {
              expect(actual, [
                0xee,
                0x55,
                0x99,
                255,
              ], reason: 'font $fontSize, join ($x,$y)');
            }
          }
        }
        expect(pixel(data, 60, 0, 0), [0, 0, 0, 255]);
        expect(pixel(data, 60, 59, 19), [0, 0, 0, 255]);
      }
    },
  );

  testWidgets('shares a baseline across different fallback font sizes', (
    tester,
  ) async {
    final editor = model(const [
      DisplayCell(text: 'M', highlight: 0),
      DisplayCell(text: '\ue001', highlight: 0),
      DisplayCell(text: ' ', highlight: 0),
    ]);
    final renderer = GridRenderer();
    addTearDown(() {
      renderer.dispose();
      editor.dispose();
    });
    final fonts = EditorFont(
      faces: const [
        EditorFontFace(
          family: 'NauvimGridTest',
          size: 20,
          ascent: 1,
          descent: 0,
          lineGap: 0,
          advance: 1,
          coverage: [(0x4d, 0x4d)],
        ),
        EditorFontFace(
          family: 'NauvimGridTest',
          size: 30,
          ascent: 1,
          descent: 0,
          lineGap: 0,
          advance: 1,
          coverage: [(0xe000, 0xe002)],
        ),
      ],
    );
    final data = await raster(
      tester,
      editor,
      renderer,
      width: 60,
      fonts: fonts,
      baseline: 20,
    );
    expect(pixel(data, 60, 10, 15), [255, 255, 255, 255]);
    expect(pixel(data, 60, 25, 12), [255, 255, 255, 255]);
    expect(pixel(data, 60, 25, 15), [0, 0, 0, 255]);
  });

  testWidgets('invalidates cached rows when the shared baseline changes', (
    tester,
  ) async {
    final editor = model(const [DisplayCell(text: 'M', highlight: 0)]);
    final renderer = GridRenderer();
    addTearDown(() {
      renderer.dispose();
      editor.dispose();
    });
    final first = await raster(
      tester,
      editor,
      renderer,
      width: 10,
      cellWidth: 10,
      fontSize: 10,
      baseline: 12,
    );
    final second = await raster(
      tester,
      editor,
      renderer,
      width: 10,
      cellWidth: 10,
      fontSize: 10,
      baseline: 18,
    );
    expect(pixel(first, 10, 5, 5), [255, 255, 255, 255]);
    expect(pixel(second, 10, 5, 5), [0, 0, 0, 255]);
    expect(pixel(first, 10, 5, 11), [0, 0, 0, 255]);
    expect(pixel(second, 10, 5, 11), [255, 255, 255, 255]);
  });

  testWidgets('fills fractional cell boundaries without background seams', (
    tester,
  ) async {
    final editor = model(
      [
        for (var col = 0; col < 8; col++)
          DisplayCell(text: ' ', highlight: col.isEven ? 1 : 2),
      ],
      highlights: [background(1), background(2)],
    );
    final renderer = GridRenderer();
    addTearDown(() {
      renderer.dispose();
      editor.dispose();
    });
    final data = await raster(
      tester,
      editor,
      renderer,
      width: 60,
      cellWidth: 7.3,
      offset: const Offset(.25, .4),
    );
    for (var x = 1; x < 58; x++) {
      expect(pixel(data, 60, x, 10), [
        0xee,
        0x55,
        0x99,
        255,
      ], reason: 'pixel $x');
    }
  });

  testWidgets(
    'fits both sides of an overwide private-use glyph into one cell',
    (tester) async {
      final editor = model(const [
        DisplayCell(text: '\ue000', highlight: 0),
        DisplayCell(text: ' ', highlight: 0),
      ]);
      final renderer = GridRenderer();
      addTearDown(() {
        renderer.dispose();
        editor.dispose();
      });
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: const TextSpan(
          text: '\ue000',
          style: TextStyle(
            fontFamily: 'NauvimGridTest',
            fontSize: 20,
            height: 1,
          ),
        ),
      )..layout();
      expect(painter.width, closeTo(40, 0.001));
      painter.dispose();
      final data = await raster(tester, editor, renderer, width: 40);
      expect(pixel(data, 40, 3, 10), [255, 255, 255, 255]);
      expect(pixel(data, 40, 16, 10), [255, 255, 255, 255]);
      expect(pixel(data, 40, 10, 10), [0, 0, 0, 255]);
      expect(pixel(data, 40, 25, 10), [0, 0, 0, 255]);
    },
  );

  testWidgets('uses Neovim continuation cells as the allocated glyph width', (
    tester,
  ) async {
    final editor = model(const [
      DisplayCell(text: '\ue000', highlight: 0),
      DisplayCell(text: '', highlight: 0),
      DisplayCell(text: ' ', highlight: 0),
    ]);
    final renderer = GridRenderer();
    addTearDown(() {
      renderer.dispose();
      editor.dispose();
    });
    final data = await raster(tester, editor, renderer, width: 60);
    expect(pixel(data, 60, 8, 10), [255, 255, 255, 255]);
    expect(pixel(data, 60, 32, 10), [255, 255, 255, 255]);
    expect(pixel(data, 60, 16, 10), [0, 0, 0, 255]);
    expect(pixel(data, 60, 45, 10), [0, 0, 0, 255]);
  });

  testWidgets('paints mixed-width preedit at the committed glyph positions', (
    tester,
  ) async {
    final composing = model(_emptyPreeditRow, cursor: _preeditCursor);
    final committed = model(const [
      DisplayCell(text: ' ', highlight: 0),
      DisplayCell(text: 'M', highlight: 0),
      DisplayCell(text: '日', highlight: 0),
      DisplayCell(text: '', highlight: 0),
      DisplayCell(text: 'x', highlight: 0),
      DisplayCell(text: ' ', highlight: 0),
    ]);
    final renderer = GridRenderer();
    addTearDown(() {
      renderer.dispose();
      composing.dispose();
      committed.dispose();
    });
    final fonts = EditorFont(
      faces: const [
        EditorFontFace(
          family: 'NauvimGridTest',
          size: 20,
          ascent: 1,
          descent: 0,
          lineGap: 0,
          advance: 1,
          coverage: [(0x4d, 0x4d)],
        ),
        EditorFontFace(
          family: 'NauvimGridTest',
          size: 25,
          ascent: 1,
          descent: 0,
          lineGap: 0,
          advance: 1,
          coverage: [(0x78, 0x78), (0x65e5, 0x65e5)],
        ),
      ],
    );
    const width = 120;
    final preedit = await raster(
      tester,
      composing,
      renderer,
      width: width,
      baseline: 16,
      fonts: fonts,
      preedit: GridPreedit(
        const EditorPreedit(text: 'M日x', selectionStart: -1, selectionEnd: -1),
      ),
    );
    final grid = await raster(
      tester,
      committed,
      renderer,
      width: width,
      baseline: 16,
      fonts: fonts,
    );

    // Check ink for the Latin glyphs on either side of the two-cell glyph.
    expect(pixel(grid, width, 30, 8), [255, 255, 255, 255]);
    expect(pixel(grid, width, 84, 8), [255, 255, 255, 255]);
    // Compare everything above the underline, including the full glyphs.
    for (var y = 0; y < 18; y++) {
      for (var x = 0; x < width; x++) {
        expect(
          pixel(preedit, width, x, y),
          pixel(grid, width, x, y),
          reason: 'pixel ($x, $y)',
        );
      }
    }
  });

  testWidgets('marks preedit selection and caret boundaries', (tester) async {
    final composing = model(_emptyPreeditRow, cursor: _preeditCursor);
    final renderer = GridRenderer();
    addTearDown(() {
      renderer.dispose();
      composing.dispose();
    });
    const width = 120;
    const ink = [255, 255, 255, 255];
    const background = [0, 0, 0, 255];

    Future<ByteData> sample(TextSelection selection) => raster(
      tester,
      composing,
      renderer,
      width: width,
      baseline: 16,
      preedit: GridPreedit(
        EditorPreedit(
          text: 'M日x',
          selectionStart: selection.baseOffset,
          selectionEnd: selection.extentOffset,
        ),
      ),
    );

    final plain = await sample(const TextSelection.collapsed(offset: 3));
    final selected = await sample(
      const TextSelection(baseOffset: 2, extentOffset: 1),
    );
    for (final x in [30, 50, 70, 90]) {
      expect(pixel(plain, width, x, 18), ink);
      expect(pixel(plain, width, x, 17), background);
      expect(pixel(selected, width, x, 18), ink);
    }
    for (final x in [39, 80]) {
      expect(pixel(selected, width, x, 17), background);
    }
    for (final x in [40, 79]) {
      expect(pixel(selected, width, x, 17), ink);
    }
    for (final x in [19, 100]) {
      expect(pixel(selected, width, x, 18), background);
    }

    final start = await sample(const TextSelection.collapsed(offset: 0));
    final inside = await sample(const TextSelection.collapsed(offset: 2));
    expect(pixel(start, width, 20, 15), ink);
    expect(pixel(inside, width, 80, 15), ink);
    expect(pixel(plain, width, 100, 15), ink);
    expect(pixel(plain, width, 80, 15), background);
    expect(pixel(inside, width, 70, 17), background);
  });

  testWidgets('keeps narrower ordinary glyphs at their natural width', (
    tester,
  ) async {
    final editor = model(const [DisplayCell(text: 'x', highlight: 0)]);
    final renderer = GridRenderer();
    addTearDown(() {
      renderer.dispose();
      editor.dispose();
    });
    final data = await raster(
      tester,
      editor,
      renderer,
      width: 30,
      cellWidth: 30,
    );
    expect(pixel(data, 30, 4, 10), [255, 255, 255, 255]);
    expect(pixel(data, 30, 16, 10), [255, 255, 255, 255]);
    expect(pixel(data, 30, 25, 10), [0, 0, 0, 255]);
  });

  testWidgets(
    'preserves ink beyond the advance and clips it at the grid edge',
    (tester) async {
      final editor = model(const [
        DisplayCell(text: '\ue001', highlight: 0),
        DisplayCell(text: ' ', highlight: 0),
      ]);
      final bounded = model(const [DisplayCell(text: '\ue001', highlight: 0)]);
      final renderer = GridRenderer();
      addTearDown(() {
        renderer.dispose();
        editor.dispose();
        bounded.dispose();
      });
      final data = await raster(tester, editor, renderer, width: 40);
      expect(pixel(data, 40, 30, 10), [255, 255, 255, 255]);
      expect(pixel(data, 40, 38, 10), [0, 0, 0, 255]);
      final clipped = await raster(tester, bounded, renderer, width: 40);
      expect(pixel(clipped, 40, 30, 10), [0, 0, 0, 255]);
    },
  );

  testWidgets('preserves negative left-bearing ink across cell boundaries', (
    tester,
  ) async {
    final editor = model(const [
      DisplayCell(text: ' ', highlight: 0),
      DisplayCell(text: '\ue002', highlight: 0),
      DisplayCell(text: ' ', highlight: 0),
    ]);
    final renderer = GridRenderer();
    addTearDown(() {
      renderer.dispose();
      editor.dispose();
    });
    final data = await raster(tester, editor, renderer, width: 60);
    expect(pixel(data, 60, 19, 10), [255, 255, 255, 255]);
    // Sample far enough from the glyph edge to avoid antialiasing.
    expect(pixel(data, 60, 16, 10), [0, 0, 0, 255]);
    expect(pixel(data, 60, 36, 10), [255, 255, 255, 255]);
  });
}

const _preeditCursor = DisplayCursor(
  grid: 1,
  row: 0,
  col: 1,
  shape: 'block',
  percentage: 100,
);

const _emptyPreeditRow = [
  DisplayCell(text: ' ', highlight: 0),
  DisplayCell(text: ' ', highlight: 0),
  DisplayCell(text: ' ', highlight: 0),
  DisplayCell(text: ' ', highlight: 0),
  DisplayCell(text: ' ', highlight: 0),
  DisplayCell(text: ' ', highlight: 0),
];

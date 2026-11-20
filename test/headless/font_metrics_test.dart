import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nauvim_flutter/nauvim.dart';

const latin = EditorFontFace(
  family: 'Latin',
  size: 20,
  ascent: .8,
  descent: .2,
  lineGap: 0,
  advance: .5,
  coverage: [(0x20, 0x7e), (0x300, 0x36f)],
);
const symbols = EditorFontFace(
  family: 'Symbols',
  size: 30,
  ascent: 1.5,
  descent: .5,
  lineGap: .2,
  advance: 1,
  coverage: [(0xe000, 0xf8ff)],
);
const cjk = EditorFontFace(
  family: 'CJK',
  size: 24,
  ascent: 1,
  descent: .3,
  lineGap: .1,
  advance: .5,
  coverage: [(0x3000, 0x9fff)],
);

void main() {
  test('uses primary metrics while retaining ordered fallback sizes', () {
    final font = EditorFont(faces: const [latin, symbols, cjk]);
    expect(font.faceFor('M'), same(latin));
    expect(font.faceFor('a\u0301'), same(latin));
    expect(font.faceFor('\ue000'), same(symbols));
    expect(font.faceFor('界'), same(cjk));
    expect(font.faceFor('\ue000').size, 30);
    expect(font.faceFor('界').size, 24);
    final cells = CellMetrics.fromFont(font, 1);
    expect((cells.width, cells.height, cells.baseline), (10, 20, 16));
    final primaryOnly = CellMetrics.fromFont(
      EditorFont(faces: const [latin]),
      1,
    );
    expect(
      (cells.width, cells.height, cells.baseline),
      (primaryOnly.width, primaryOnly.height, primaryOnly.baseline),
    );
  });

  test('aligns cells and the common baseline to device pixels', () {
    final font = EditorFont(faces: const [latin, symbols]);
    final cells = CellMetrics.fromFont(font, 1.25);
    expect((cells.width, cells.height, cells.baseline), (10.4, 20, 16));
    for (final scale in [1.0, 1.25, 1.5, 2.0]) {
      final cells = CellMetrics.fromFont(font, scale);
      expect(cells.width * scale, (cells.width * scale).roundToDouble());
      expect(cells.height * scale, (cells.height * scale).roundToDouble());
      for (var n = 1; n <= 120; n++) {
        final viewport = EditorViewport(
          font: font,
          size: Size(n * cells.width, n * cells.height),
          cellWidth: cells.width,
          cellHeight: cells.height,
          devicePixelRatio: scale,
        );
        expect((viewport.columns, viewport.rows), (n, n), reason: '$scale, $n');
      }
    }
  });
}

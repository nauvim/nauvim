import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nauvim_flutter/src/widgets/ime_overlay.dart';

void main() {
  testWidgets('anchors preedit at the row baseline', (tester) async {
    await tester.pumpWidget(_preedit(anchor: 36));

    final preedit = find.byType(ImePreedit);
    expect(tester.getSize(preedit).height, 28);
    expect(tester.getTopLeft(preedit).dy, 36 - 20);
  });

  testWidgets('paints the reported segment and interior caret', (tester) async {
    const boundary = ValueKey('preedit');

    Future<Color Function(int, int)> sample(TextSelection selection) async {
      await tester.pumpWidget(
        _preedit(boundary: boundary, selection: selection),
      );
      final render = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundary),
      );
      final read = await tester.runAsync(() async {
        final image = await render.toImage();
        final width = image.width;
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        image.dispose();

        return (int x, int y) {
          final index = (y * width + x) * 4;
          return Color.fromARGB(
            data.getUint8(index + 3),
            data.getUint8(index),
            data.getUint8(index + 1),
            data.getUint8(index + 2),
          );
        };
      });
      return read!;
    }

    var pixel = await sample(const TextSelection.collapsed(offset: 4));
    expect(pixel(8, 22), _ink);
    expect(pixel(8, 21), _background);

    pixel = await sample(const TextSelection(baseOffset: 1, extentOffset: 3));
    expect(pixel(8, 22), _ink);
    expect(pixel(8, 21), _background);
    expect(pixel(24, 21), _ink);
    expect(pixel(40, 21), _ink);
    expect(pixel(56, 21), _background);

    pixel = await sample(const TextSelection.collapsed(offset: 2));
    expect(pixel(32, 19), _ink);
    expect(pixel(31, 19), _background);
    expect(pixel(24, 21), _background);
  });
}

const _ink = Color(0xffeeeeee);
const _background = Color(0xff121212);

Widget _preedit({Key? boundary, TextSelection? selection, double? anchor}) {
  final preedit = RepaintBoundary(
    key: boundary,
    child: ImePreedit(
      text: 'ABCD',
      style: const TextStyle(fontFamily: 'Ahem', fontSize: 16, color: _ink),
      background: _background,
      baseline: 20,
      lineHeight: 28,
      selection: selection ?? const TextSelection.collapsed(offset: -1),
      spans: const [
        TextSpan(
          text: 'ABCD',
          style: TextStyle(color: Color(0x00000000)),
        ),
      ],
    ),
  );
  return MediaQuery(
    data: const MediaQueryData(devicePixelRatio: 1),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: anchor == null
            ? preedit
            : Baseline(
                baseline: anchor,
                baselineType: TextBaseline.alphabetic,
                child: preedit,
              ),
      ),
    ),
  );
}

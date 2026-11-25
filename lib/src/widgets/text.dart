import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../headless/editor_model.dart';
import '../headless/protocol.dart';
import 'paint_style.dart';

/// Converts a Neovim UTF-8 byte position to Flutter's UTF-16 text position.
int byteOffsetToUtf16(String text, int offset) {
  var bytes = 0;
  var units = 0;
  for (final rune in text.runes) {
    final length = rune < 0x80
        ? 1
        : (rune < 0x800 ? 2 : (rune < 0x10000 ? 3 : 4));
    if (bytes + length > offset) break;
    bytes += length;
    units += rune > 0xffff ? 2 : 1;
  }
  return units;
}

TextStyle editorTextStyle(
  List<String> families,
  double size, {
  double? lineHeight = 1.2,
  List<(String, double)> variations = const [],
}) => TextStyle(
  fontFamily: families.first,
  fontFamilyFallback: families.skip(1).toList(),
  fontSize: size,
  height: lineHeight,
  fontVariations: [
    for (final axis in variations) ui.FontVariation(axis.$1, axis.$2),
  ],
  fontFeatures: const [
    ui.FontFeature.disable('liga'),
    ui.FontFeature.disable('clig'),
  ],
);

TextPainter widgetTextPainter(
  DisplayWidget item,
  EditorModel model,
  TextStyle style, {
  EditorPaintStyle paintStyle = const EditorPaintStyle(),
  List<DisplayChunk>? chunks,
}) => TextPainter(
  textDirection: TextDirection.ltr,
  textScaler: TextScaler.noScaling,
  text: TextSpan(
    style: style,
    children: [
      highlightedChunks(chunks ?? item.chunks, model, paintStyle: paintStyle),
    ],
  ),
)..layout();

double commandLineOffset(
  DisplayWidget item,
  EditorModel model,
  TextStyle style,
  int byteOffset, {
  EditorPaintStyle paintStyle = const EditorPaintStyle(),
}) {
  final text = item.chunks.map((c) => c.text).join();
  final painter = widgetTextPainter(item, model, style, paintStyle: paintStyle);
  final offset = painter.getOffsetForCaret(
    TextPosition(offset: byteOffsetToUtf16(text, byteOffset)),
    Rect.zero,
  );
  painter.dispose();
  return offset.dx;
}

TextDecorationStyle decorationStyle(String? decoration) => switch (decoration) {
  'undercurl' => TextDecorationStyle.wavy,
  'underdouble' => TextDecorationStyle.double,
  'underdotted' => TextDecorationStyle.dotted,
  'underdashed' => TextDecorationStyle.dashed,
  _ => TextDecorationStyle.solid,
};

TextSpan highlightedChunks(
  List<DisplayChunk> chunks,
  EditorModel model, {
  EditorPaintStyle paintStyle = const EditorPaintStyle(),
}) => TextSpan(
  children: [
    for (final chunk in chunks)
      TextSpan(
        text: chunk.text,
        style: highlightStyle(
          model.highlights[chunk.highlight],
          model,
          paintStyle: paintStyle,
        ),
      ),
  ],
);

TextStyle highlightStyle(
  DisplayHighlight? highlight,
  EditorModel model, {
  EditorPaintStyle paintStyle = const EditorPaintStyle(),
}) {
  var foreground = paintStyle.resolveForeground(
    highlight?.foreground ?? model.frame?.foreground,
  );
  var background = paintStyle.resolveBackground(
    highlight?.background ?? model.frame?.background,
  );
  if (highlight?.reverse ?? false) {
    final previous = foreground;
    foreground = background;
    background = previous;
  }
  final special = highlight?.special;
  return TextStyle(
    color: foreground,
    backgroundColor: background,
    fontWeight: (highlight?.bold ?? false)
        ? FontWeight.bold
        : FontWeight.normal,
    fontStyle: (highlight?.italic ?? false)
        ? FontStyle.italic
        : FontStyle.normal,
    decoration: TextDecoration.combine([
      if ((highlight?.underline ?? false) || (highlight?.undercurl ?? false))
        TextDecoration.underline,
      if (highlight?.strikethrough ?? false) TextDecoration.lineThrough,
    ]),
    decorationStyle: decorationStyle(highlight?.decoration),
    decorationColor: special == null ? foreground : Color(0xff000000 | special),
  );
}

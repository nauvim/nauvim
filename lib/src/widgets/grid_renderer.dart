import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart' show CustomPainter;

import '../headless/editor_model.dart';
import '../headless/viewport.dart';
import 'grid_preedit.dart';
import 'paint_style.dart';
import 'powerline.dart';
import 'text.dart';

double gridAlphabeticBaseline(
  String family,
  List<String> fallback,
  double fontSize,
  double cellHeight,
) {
  final primary = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: 'M',
      style: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: fontSize,
      ),
    ),
  )..layout();
  final baseline =
      cellHeight -
      primary.height +
      primary.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  primary.dispose();
  return baseline;
}

class GridRenderer {
  final Map<(GridBuffer, int), _RowPicture> _rows = {};
  final Map<(String, int, int), TextPainter> _glyphs = {};
  String? _family;
  List<String>? _fallback;
  double? _size, _cellWidth, _cellHeight;
  Color? _foreground, _background;
  EditorFont? _fonts;
  double? _baseline;
  void dispose() {
    for (final row in _rows.values) {
      row.picture.dispose();
    }
    for (final glyph in _glyphs.values) {
      glyph.dispose();
    }
    _rows.clear();
    _glyphs.clear();
  }

  void paint(
    Canvas canvas,
    Size size,
    EditorModel model,
    String family,
    List<String> fallback,
    double fontSize,
    double cellWidth,
    double cellHeight, {
    EditorPaintStyle style = const EditorPaintStyle(),
    EditorFont? fonts,
    double? baseline,
    GridPreedit? preedit,
    double pixel = 1,
  }) {
    final frame = model.frame;
    if (frame == null) return;
    final foreground = style.resolveForeground(frame.foreground);
    final background = style.resolveBackground(frame.background);
    if (_family != family ||
        !listEquals(_fallback, fallback) ||
        _size != fontSize ||
        _cellWidth != cellWidth ||
        _cellHeight != cellHeight ||
        _foreground != foreground ||
        _background != background) {
      dispose();
      _family = family;
      _fallback = List.of(fallback);
      _size = fontSize;
      _cellWidth = cellWidth;
      _cellHeight = cellHeight;
      _foreground = foreground;
      _background = background;
    }
    if (!identical(_fonts, fonts) || _baseline != baseline) {
      dispose();
      _fonts = fonts;
      _baseline = baseline;
    }
    final alphabeticBaseline =
        baseline ??
        gridAlphabeticBaseline(family, fallback, fontSize, cellHeight);

    Color cellForeground(int id) {
      final highlight = model.highlights[id];
      final reverse = highlight?.reverse ?? false;
      final rgb = reverse ? highlight?.background : highlight?.foreground;
      return rgb == null
          ? (reverse ? background : foreground)
          : Color(0xff000000 | rgb);
    }

    Color cellBackground(int id) {
      final highlight = model.highlights[id];
      final reverse = highlight?.reverse ?? false;
      final rgb = reverse ? highlight?.foreground : highlight?.background;
      final color = rgb == null
          ? (reverse ? foreground : background)
          : Color(0xff000000 | rgb);
      final alpha = 1 - (highlight?.blend ?? 0) / 100;
      return color.withValues(alpha: color.a * alpha);
    }

    void paintCellGlyph(
      Canvas rowCanvas,
      String text,
      int highlightId,
      int col,
      int columns,
    ) {
      final highlight = model.highlights[highlightId];

      if (text.isEmpty ||
          (text == ' ' &&
              !(highlight?.underline ?? false) &&
              !(highlight?.undercurl ?? false) &&
              !(highlight?.strikethrough ?? false))) {
        return;
      }
      final cap = text == '\ue0b4' || text == '\ue0b6';
      if (cap) {
        paintPowerlineCap(
          rowCanvas,
          Rect.fromLTWH(col * cellWidth, 0, cellWidth, cellHeight),
          cellForeground(highlightId),
          left: text == '\ue0b6',
        );
        if (!(highlight?.underline ?? false) &&
            !(highlight?.undercurl ?? false) &&
            !(highlight?.strikethrough ?? false)) {
          return;
        }
      }
      final glyphKey = (text, highlightId, model.generation);
      var glyph = _glyphs[glyphKey];
      if (glyph == null) {
        if (_glyphs.length > 8192) {
          for (final value in _glyphs.values) {
            value.dispose();
          }
          _glyphs.clear();
        }
        final color = cellForeground(highlightId);
        final special = highlight?.special;
        final face = fonts?.faceFor(text);
        glyph = TextPainter(
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontFamily: face?.family ?? family,
              fontFamilyFallback: fallback,
              fontSize: face?.size ?? fontSize,
              fontVariations: face?.variations
                  .map((axis) => ui.FontVariation(axis.$1, axis.$2))
                  .toList(),
              color: cap ? const Color(0x00000000) : color,
              fontWeight: (highlight?.bold ?? false)
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontStyle: (highlight?.italic ?? false)
                  ? FontStyle.italic
                  : FontStyle.normal,
              decoration: TextDecoration.combine([
                if ((highlight?.underline ?? false) ||
                    (highlight?.undercurl ?? false))
                  TextDecoration.underline,
                if (highlight?.strikethrough ?? false)
                  TextDecoration.lineThrough,
              ]),
              decorationStyle: decorationStyle(highlight?.decoration),
              decorationColor: special == null
                  ? color
                  : Color(0xff000000 | special),
              fontFeatures: const [
                ui.FontFeature.disable('liga'),
                ui.FontFeature.disable('clig'),
              ],
            ),
          ),
        )..layout();
        _glyphs[glyphKey] = glyph;
      }
      rowCanvas.save();
      rowCanvas.translate(
        col * cellWidth,
        alphabeticBaseline -
            glyph.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      );
      // Fallback fonts may give an icon a wider advance than Neovim's
      // cell allocation. Fit that advance instead of clipping the icon.
      final width = columns * cellWidth;
      if (width > 0 && glyph.width > width) {
        rowCanvas.scale(width / glyph.width, 1);
      }
      glyph.paint(rowCanvas, Offset.zero);
      rowCanvas.restore();
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size, doAntiAlias: false);
    canvas.drawColor(background, BlendMode.src);
    final liveRows = <(GridBuffer, int)>{};
    for (final grid in model.visibleGrids) {
      final g = grid.geometry;
      canvas.save();
      canvas.translate(g.col * cellWidth, g.row * cellHeight);
      canvas.clipRect(
        Rect.fromLTWH(0, 0, g.width * cellWidth, g.height * cellHeight),
        doAntiAlias: false,
      );
      for (final entry in grid.rows.entries) {
        final key = (grid, entry.key);
        liveRows.add(key);
        var cached = _rows[key];
        final revision = grid.revisions[entry.key] ?? 0;
        if (cached == null ||
            cached.revision != revision ||
            cached.generation != model.generation) {
          cached?.picture.dispose();
          final recorder = ui.PictureRecorder();
          final rowCanvas = Canvas(recorder);
          final backgroundPaint = Paint()..isAntiAlias = false;
          for (var col = 0; col < entry.value.length;) {
            final cell = entry.value[col];
            var end = col + 1;
            while (end < entry.value.length &&
                entry.value[end].highlight == cell.highlight) {
              end++;
            }
            rowCanvas.drawRect(
              Rect.fromLTWH(
                col * cellWidth,
                0,
                (end - col) * cellWidth,
                cellHeight,
              ),
              backgroundPaint..color = cellBackground(cell.highlight),
            );
            col = end;
          }
          // Terminal glyphs can overhang their advance (for example, icons and
          // italic letters). Keep that ink inside the row, not inside one cell.
          rowCanvas.clipRect(
            Rect.fromLTWH(0, 0, g.width * cellWidth, cellHeight),
            doAntiAlias: false,
          );
          for (var col = 0; col < entry.value.length; col++) {
            final cell = entry.value[col];
            if (cell.text.isEmpty) continue;
            var columns = 1;
            while (col + columns < entry.value.length &&
                entry.value[col + columns].text.isEmpty) {
              columns++;
            }
            paintCellGlyph(rowCanvas, cell.text, cell.highlight, col, columns);
          }
          cached = _RowPicture(
            recorder.endRecording(),
            revision,
            model.generation,
          );
          _rows[key] = cached;
        }
        canvas.save();
        canvas.translate(0, entry.key * cellHeight);
        canvas.drawPicture(cached.picture);
        canvas.restore();
        if (model.selectedColumns(g.id, entry.key) case final range?) {
          canvas.drawRect(
            Rect.fromLTWH(
              range.$1 * cellWidth,
              entry.key * cellHeight,
              (range.$2 - range.$1) * cellWidth,
              cellHeight,
            ),
            Paint()..color = style.selectionColor,
          );
        }
      }
      final cursor = frame.cursor;
      if (preedit != null &&
          cursor != null &&
          cursor.grid == g.id &&
          !frame.busy &&
          cursor.col >= 0 &&
          cursor.col < g.width &&
          cursor.row >= 0 &&
          cursor.row < g.height) {
        final row = grid.rows[cursor.row];
        final highlightId = row != null && cursor.col < row.length
            ? row[cursor.col].highlight
            : 0;
        final left = cursor.col * cellWidth;
        final right = (cursor.col + preedit.columns) * cellWidth;
        final bottom = math.min(cellHeight, alphabeticBaseline + 3 * pixel);
        final ink = Paint()
          ..color = cellForeground(highlightId)
          ..isAntiAlias = false;
        canvas.save();
        canvas.translate(0, cursor.row * cellHeight);
        canvas.clipRect(
          Rect.fromLTWH(0, 0, g.width * cellWidth, cellHeight),
          doAntiAlias: false,
        );
        canvas.drawRect(
          Rect.fromLTRB(left, 0, right, cellHeight),
          Paint()
            ..color = Color.alphaBlend(cellBackground(highlightId), background)
            ..isAntiAlias = false,
        );
        final selection = preedit.selection;
        var col = cursor.col;
        for (final cell in preedit.cells) {
          paintCellGlyph(canvas, cell.text, highlightId, col, cell.columns);
          col += cell.columns;
        }
        canvas.drawRect(
          Rect.fromLTRB(left, bottom - pixel, right, bottom),
          ink,
        );
        if (preedit.segments.isNotEmpty) {
          var segmentCol = cursor.col;
          for (final cell in preedit.cells) {
            final start = segmentCol * cellWidth;
            final end = (segmentCol + cell.columns) * cellWidth;
            for (final segment in preedit.segments) {
              if (segment.start >= cell.end || segment.end <= cell.start) {
                continue;
              }
              final thickness = segment.selected ? 3 * pixel : 2 * pixel;
              canvas.drawRect(
                Rect.fromLTRB(start, bottom - thickness, end, bottom - pixel),
                ink,
              );
              if (segment.end <= cell.end &&
                  segment.end < preedit.text.length) {
                canvas.drawRect(
                  Rect.fromLTRB(end - pixel, bottom - 4 * pixel, end, bottom),
                  ink,
                );
              }
            }
            segmentCol += cell.columns;
          }
        }
        if (selection.isValid) {
          col = cursor.col;
          var caret = left;
          for (final cell in preedit.cells) {
            final start = col * cellWidth;
            final end = (col + cell.columns) * cellWidth;
            if (!selection.isCollapsed &&
                selection.start < cell.end &&
                selection.end > cell.start) {
              canvas.drawRect(
                Rect.fromLTRB(start, bottom - 2 * pixel, end, bottom),
                ink,
              );
            }
            if (selection.start > cell.start) caret = end;
            col += cell.columns;
          }
          if (selection.isCollapsed) {
            canvas.drawRect(
              Rect.fromLTRB(
                caret,
                math.max(0, alphabeticBaseline - 4 * pixel),
                caret + pixel,
                bottom,
              ),
              ink,
            );
          }
        }
        canvas.restore();
      } else if (cursor != null && cursor.grid == g.id && !frame.busy) {
        final percent = cursor.percentage / 100;
        final width = cursor.shape == 'vertical'
            ? cellWidth * percent
            : cellWidth;
        final height = cursor.shape == 'horizontal'
            ? cellHeight * percent
            : cellHeight;
        final y =
            cursor.row * cellHeight +
            (cursor.shape == 'horizontal' ? cellHeight - height : 0);
        canvas.drawRect(
          Rect.fromLTWH(cursor.col * cellWidth, y, width, height),
          Paint()
            ..color = (style.cursorColor ?? foreground).withValues(
              alpha: style.cursorOpacity,
            ),
        );
      }
      canvas.restore();
    }
    final stale = _rows.keys.where((key) => !liveRows.contains(key)).toList();
    for (final key in stale) {
      _rows.remove(key)?.picture.dispose();
    }
    canvas.restore();
  }
}

class _RowPicture {
  _RowPicture(this.picture, this.revision, this.generation);
  final ui.Picture picture;
  final int revision, generation;
}

class EditorPainter extends CustomPainter {
  EditorPainter(
    this.model,
    this.renderer,
    this.family,
    this.fallback,
    this.fontSize,
    this.cellWidth,
    this.cellHeight, {
    this.style = const EditorPaintStyle(),
    this.fonts,
    this.baseline,
    this.preedit,
    this.pixel = 1,
  }) : super(repaint: model);
  final EditorModel model;
  final GridRenderer renderer;
  final String family;
  final List<String> fallback;
  final double fontSize, cellWidth, cellHeight;
  final EditorFont? fonts;
  final double? baseline;
  final GridPreedit? preedit;
  final double pixel;
  final EditorPaintStyle style;
  @override
  void paint(Canvas canvas, Size size) => renderer.paint(
    canvas,
    size,
    model,
    family,
    fallback,
    fontSize,
    cellWidth,
    cellHeight,
    style: style,
    fonts: fonts,
    baseline: baseline,
    preedit: preedit,
    pixel: pixel,
  );
  @override
  bool shouldRepaint(EditorPainter oldDelegate) =>
      oldDelegate.family != family ||
      !listEquals(oldDelegate.fallback, fallback) ||
      oldDelegate.fontSize != fontSize ||
      oldDelegate.cellWidth != cellWidth ||
      oldDelegate.cellHeight != cellHeight ||
      oldDelegate.fonts != fonts ||
      oldDelegate.baseline != baseline ||
      oldDelegate.preedit != preedit ||
      oldDelegate.pixel != pixel ||
      oldDelegate.model != model ||
      oldDelegate.style.selectionColor != style.selectionColor ||
      oldDelegate.style.cursorColor != style.cursorColor ||
      oldDelegate.style.cursorOpacity != style.cursorOpacity ||
      oldDelegate.style.fallbackForeground != style.fallbackForeground ||
      oldDelegate.style.fallbackBackground != style.fallbackBackground;
}

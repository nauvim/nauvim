import 'dart:math' as math;

import 'package:flutter/rendering.dart'
    show MatrixUtils, PaintingContext, RenderAbstractViewport, RenderBox;
import 'package:flutter/widgets.dart';

import '../headless/editor_model.dart';
import '../headless/viewport.dart';

/// The cursor cell in canvas coordinates when any part of it is visible.
Rect? imeGridCaret(EditorModel model, EditorViewport viewport) {
  final frame = model.frame;
  if (frame == null || frame.busy) return null;
  final cursor = frame.cursor;
  if (cursor == null) return null;

  final grid = model.grids[cursor.grid]?.geometry;
  if (grid == null ||
      grid.hidden ||
      cursor.col < 0 ||
      cursor.col >= grid.width ||
      cursor.row < 0 ||
      cursor.row >= grid.height) {
    return null;
  }

  final cell = Rect.fromLTWH(
    (grid.col + cursor.col) * viewport.cellWidth,
    (grid.row + cursor.row) * viewport.cellHeight,
    viewport.cellWidth,
    viewport.cellHeight,
  );
  final visible = cell.intersect(Offset.zero & viewport.size);
  return visible.isFinite && !visible.isEmpty ? cell : null;
}

/// The command-line caret in global coordinates after layout and scrolling.
Rect? imeCommandLineCaret(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;

  var visible = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
  for (var parent = box.parent; parent != null; parent = parent.parent) {
    if (parent is RenderAbstractViewport) {
      final viewport = MatrixUtils.transformRect(
        parent.getTransformTo(null),
        parent.paintBounds,
      );
      visible = visible.intersect(viewport);
    }
  }
  return visible.isFinite && !visible.isEmpty ? visible : null;
}

/// Preedit display for text that has not been committed to the editor.
class ImePreedit extends StatelessWidget {
  const ImePreedit({
    super.key,
    required this.text,
    required this.style,
    required this.background,
    required this.baseline,
    required this.lineHeight,
    this.selection = const TextSelection.collapsed(offset: -1),
    this.spans,
  });

  final String text;
  final TextStyle style;
  final Color background;
  final double baseline;
  final double lineHeight;
  final TextSelection selection;

  /// Styled runs of [text] that inherit [style].
  final List<InlineSpan>? spans;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Semantics(
      label: text,
      child: _PreeditBox((
        span: TextSpan(
          text: spans == null ? text : null,
          children: spans,
          style: style.copyWith(decoration: TextDecoration.none),
        ),
        textLength: text.length,
        selection: selection,
        background: background,
        foreground:
            style.foreground?.color ?? style.color ?? const Color(0xff000000),
        baseline: baseline,
        lineHeight: lineHeight,
        pixel:
            1 /
            (MediaQuery.maybeDevicePixelRatioOf(context) ??
                View.of(context).devicePixelRatio),
      )),
    ),
  );
}

typedef _PreeditFormat = ({
  TextSpan span,
  int textLength,
  TextSelection selection,
  Color background,
  Color foreground,
  double baseline,
  double lineHeight,
  double pixel,
});

class _PreeditBox extends LeafRenderObjectWidget {
  const _PreeditBox(this.format);

  final _PreeditFormat format;

  @override
  _RenderPreedit createRenderObject(BuildContext context) =>
      _RenderPreedit(format);

  @override
  void updateRenderObject(BuildContext context, _RenderPreedit renderObject) {
    renderObject.format = format;
  }
}

class _RenderPreedit extends RenderBox {
  _RenderPreedit(this._format)
    : _painter = TextPainter(
        text: _format.span,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      );

  _PreeditFormat _format;
  final TextPainter _painter;

  set format(_PreeditFormat value) {
    final old = _format;
    if (value == old) return;

    _format = value;
    if (value.span != old.span ||
        value.baseline != old.baseline ||
        value.lineHeight != old.lineHeight) {
      _painter.text = value.span;
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    _painter.layout();
    return constraints.constrain(Size(_painter.width, _format.lineHeight));
  }

  @override
  double computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => _format.baseline;

  @override
  void performLayout() => size = computeDryLayout(constraints);

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      _format.baseline;

  @override
  void paint(PaintingContext context, Offset offset) {
    final format = _format;
    final canvas = context.canvas;
    final bounds = offset & size;
    canvas.save();
    canvas.clipRect(bounds, doAntiAlias: false);
    canvas.drawRect(bounds, Paint()..color = format.background);
    final baseline = offset.dy + format.baseline;
    final textTop =
        baseline -
        _painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    _painter.paint(canvas, Offset(offset.dx, textTop));

    final pixel = format.pixel;
    final bottom = math.min(bounds.bottom, baseline + 3 * pixel);
    final ink = Paint()..color = format.foreground;
    void underline(TextSelection selection, double thickness) {
      for (final box in _painter.getBoxesForSelection(selection)) {
        canvas.drawRect(
          Rect.fromLTRB(
            offset.dx + box.left,
            bottom - thickness,
            offset.dx + box.right,
            bottom,
          ),
          ink,
        );
      }
    }

    underline(
      TextSelection(baseOffset: 0, extentOffset: format.textLength),
      pixel,
    );
    final selection = format.selection;
    if (selection.isValid && selection.end <= format.textLength) {
      if (!selection.isCollapsed) {
        underline(selection, 2 * pixel);
      } else if (selection.start > 0 && selection.end < format.textLength) {
        final caret = _painter.getOffsetForCaret(
          TextPosition(offset: selection.start, affinity: selection.affinity),
          Rect.zero,
        );
        canvas.drawRect(
          Rect.fromLTRB(
            offset.dx + caret.dx,
            math.max(bounds.top, baseline - 4 * pixel),
            offset.dx + caret.dx + pixel,
            bottom,
          ),
          ink,
        );
      }
    }
    canvas.restore();
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}

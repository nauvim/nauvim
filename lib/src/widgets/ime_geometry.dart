import 'package:flutter/rendering.dart'
    show MatrixUtils, RenderAbstractViewport, RenderBox;
import 'package:flutter/widgets.dart';

import '../headless/editor_model.dart';
import '../headless/viewport.dart';

/// The cursor cell in canvas coordinates when any part of it is visible.
Rect? imeGridCaret(
  EditorModel model,
  EditorViewport viewport, {
  int columns = 1,
}) {
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
    columns.clamp(1, grid.width - cursor.col) * viewport.cellWidth,
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

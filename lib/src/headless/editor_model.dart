import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'protocol.dart';

class GridBuffer {
  GridBuffer(this.geometry);
  DisplayGrid geometry;
  final Map<int, List<DisplayCell>> rows = {};
  final Map<int, int> revisions = {};
  int _revision = 0;
  void update(DisplayRow row) {
    rows[row.row] = row.cells;
    revisions[row.row] = ++_revision;
  }
}

class CellPoint {
  const CellPoint(this.grid, this.row, this.col);
  final int grid, row, col;
}

class EditorModel extends ChangeNotifier {
  final Map<int, GridBuffer> grids = {};
  final Map<int, DisplayHighlight> highlights = {};
  DisplayFrame? frame;
  List<DisplayWidget> widgets = const [];
  CellPoint? selectionStart, selectionEnd;
  int generation = 0;
  List<GridBuffer> _visible = const [];

  void apply(DisplayFrame update) {
    final ids = update.grids.map((g) => g.id).toSet();
    var layoutChanged = update.full || !setEquals(ids, grids.keys.toSet());
    grids.removeWhere((id, _) => !ids.contains(id));
    for (final geometry in update.grids) {
      final grid = grids.putIfAbsent(geometry.id, () => GridBuffer(geometry));
      layoutChanged |= grid.geometry != geometry;
      if (grid.geometry.width != geometry.width ||
          grid.geometry.height != geometry.height) {
        grid.rows.clear();
        grid.revisions.clear();
        clearSelection(notify: false);
      }
      grid.geometry = geometry;
    }
    for (final row in update.rows) {
      grids[row.grid]?.update(row);
    }
    for (final hl in update.highlights) {
      highlights[hl.id] = hl;
    }
    if (update.highlights.isNotEmpty ||
        frame?.foreground != update.foreground ||
        frame?.background != update.background) {
      generation++;
    }
    if (update.widgets != null) widgets = update.widgets!;
    frame = update;
    if (layoutChanged) {
      _visible = grids.values.where((g) => !g.geometry.hidden).toList()
        ..sort((a, b) {
          final z = a.geometry.zindex.compareTo(b.geometry.zindex);
          if (z != 0) return z;
          final order = a.geometry.order.compareTo(b.geometry.order);
          return order == 0 ? a.geometry.id.compareTo(b.geometry.id) : order;
        });
    }
    if (!grids.containsKey(selectionStart?.grid)) clearSelection(notify: false);
    notifyListeners();
  }

  void clear() {
    grids.clear();
    _visible = const [];
    highlights.clear();
    frame = null;
    widgets = const [];
    generation++;
    clearSelection(notify: false);
    notifyListeners();
  }

  List<GridBuffer> get visibleGrids => _visible;

  CellPoint? hit(double x, double y, double cellWidth, double cellHeight) {
    for (final grid in visibleGrids.reversed) {
      final g = grid.geometry;
      final row = (y / cellHeight - g.row).floor();
      final col = (x / cellWidth - g.col).floor();
      if (row >= 0 && col >= 0 && row < g.height && col < g.width) {
        return CellPoint(g.id, row, col);
      }
    }
    return null;
  }

  void beginSelection(CellPoint point) {
    selectionStart = point;
    selectionEnd = point;
    notifyListeners();
  }

  void extendSelection(CellPoint point) {
    if (point.grid != selectionStart?.grid) return;
    selectionEnd = point;
    notifyListeners();
  }

  void clearSelection({bool notify = true}) {
    selectionStart = null;
    selectionEnd = null;
    if (notify) notifyListeners();
  }

  /// Returns the selected half-open column range in one row.
  (int, int)? selectedColumns(int grid, int row) {
    final start = selectionStart, end = selectionEnd;
    final width = grids[grid]?.geometry.width;
    if (start == null ||
        end == null ||
        width == null ||
        width == 0 ||
        grid != start.grid) {
      return null;
    }
    final a = start.row * width + start.col;
    final b = end.row * width + end.col;
    final left = math.max(0, math.min(a, b) - row * width);
    final right = math.min(width, math.max(a, b) - row * width + 1);
    return left < right ? (left, right) : null;
  }

  bool isSelected(int grid, int row, int col) {
    final start = selectionStart, end = selectionEnd;
    final width = grids[grid]?.geometry.width;
    if (start == null || end == null || width == null || grid != start.grid) {
      return false;
    }
    final a = start.row * width + start.col, b = end.row * width + end.col;
    final value = row * width + col;
    return value >= math.min(a, b) && value <= math.max(a, b);
  }

  String selectedText() {
    final start = selectionStart, end = selectionEnd;
    final grid = grids[start?.grid];
    if (start == null ||
        end == null ||
        grid == null ||
        grid.geometry.width == 0) {
      return '';
    }
    final width = grid.geometry.width;
    final a = math.min(
      start.row * width + start.col,
      end.row * width + end.col,
    );
    final b = math.max(
      start.row * width + start.col,
      end.row * width + end.col,
    );
    final lines = <String>[];
    for (var row = a ~/ width; row <= b ~/ width; row++) {
      final cells = grid.rows[row] ?? const <DisplayCell>[];
      final text = StringBuffer();
      for (
        var col = row == a ~/ width ? a % width : 0;
        col < width && (row != b ~/ width || col <= b % width);
        col++
      ) {
        if (col < cells.length) text.write(cells[col].text);
      }
      lines.add(text.toString());
    }
    return lines.join('\n');
  }
}

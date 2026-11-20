import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'protocol.dart';

/// One configured face, with em metrics and compact Unicode coverage.
final class EditorFontFace {
  const EditorFontFace({
    required this.family,
    required this.size,
    required this.ascent,
    required this.descent,
    required this.lineGap,
    required this.advance,
    required this.coverage,
    this.variations = const [],
  });

  /// The rendering family identifier, including a private alias for loaded faces.
  final String family;
  final double size, ascent, descent, lineGap, advance;
  final List<(int, int)> coverage;

  /// OpenType axis tags and user-space values for the selected default instance.
  final List<(String, double)> variations;

  bool covers(int rune) {
    var lo = 0, hi = coverage.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      final range = coverage[mid];
      if (rune < range.$1) {
        hi = mid;
      } else if (rune > range.$2) {
        lo = mid + 1;
      } else {
        return true;
      }
    }
    return false;
  }
}

/// Ordered faces and sizes. The primary face defines the fixed cell metrics.
final class EditorFont {
  factory EditorFont({required Iterable<EditorFontFace> faces}) {
    final entries = List<EditorFontFace>.unmodifiable(faces);
    if (entries.isEmpty) {
      throw ArgumentError('At least one font face is required');
    }
    for (final face in entries) {
      if (![
            face.size,
            face.ascent,
            face.descent,
            face.lineGap,
            face.advance,
          ].every((v) => v.isFinite) ||
          face.size <= 0 ||
          face.ascent < 0 ||
          face.descent < 0 ||
          face.ascent + face.descent <= 0 ||
          face.lineGap < 0 ||
          face.advance <= 0) {
        throw ArgumentError(
          'Font sizes and metrics must be finite and positive',
        );
      }
    }
    return EditorFont._(
      entries,
      List.unmodifiable(entries.map((f) => f.family)),
    );
  }
  const EditorFont._(this.faces, this.families);

  /// Supplies startup layout until native font discovery completes.
  /// Attachment waits for a viewport measured from the discovered faces.
  const EditorFont.fallback()
    : faces = const [
        EditorFontFace(
          family: 'monospace',
          size: 15,
          ascent: 0.8,
          descent: 0.2,
          lineGap: 0,
          advance: 0.6,
          coverage: [(0, 0x10ffff)],
        ),
      ],
      families = const ['monospace'];

  final List<EditorFontFace> faces;
  final List<String> families;
  double get size => faces.first.size;

  EditorFontFace faceFor(String text) => faces.firstWhere(
    (face) => text.runes.every(
      (rune) =>
          rune == 0x200d ||
          (rune >= 0xfe00 && rune <= 0xfe0f) ||
          (rune >= 0xe0100 && rune <= 0xe01ef) ||
          face.covers(rune),
    ),
    orElse: () => faces.first,
  );
}

/// Device-pixel-aligned terminal cells and their shared alphabetic baseline.
final class CellMetrics {
  const CellMetrics({
    required this.width,
    required this.height,
    required this.baseline,
  });
  final double width, height, baseline;

  factory CellMetrics.fromFont(
    EditorFont font,
    double scale, {
    double lineHeight = 1,
    double heightMultiplier = 1,
    bool roundLineMetrics = false,
  }) {
    if (!scale.isFinite ||
        scale <= 0 ||
        !lineHeight.isFinite ||
        lineHeight <= 0 ||
        !heightMultiplier.isFinite ||
        heightMultiplier <= 0) {
      throw ArgumentError(
        'Display scale and line spacing must be finite and positive',
      );
    }
    final face = font.faces.first;
    final size = face.size * scale;
    final width = math.max(1, (face.advance * size).round());
    final descent = roundLineMetrics
        ? (face.descent * size).round()
        : (face.descent * size).ceil();
    final ascent = roundLineMetrics
        ? (face.ascent * size).round()
        : (face.ascent * size).ceil();
    final natural = ascent + descent + (face.lineGap * size).round();
    final height = math.max(
      1,
      (natural * lineHeight * heightMultiplier).round(),
    );
    return CellMetrics(
      width: width / scale,
      height: height / scale,
      baseline: (height - descent) / scale,
    );
  }
}

/// Client-window resize increments, with non-grid chrome as the base size.
final class WindowGrid {
  const WindowGrid({
    required this.cellWidth,
    required this.cellHeight,
    required this.baseWidth,
    required this.baseHeight,
    this.minRows = 1,
  });
  final double cellWidth, cellHeight, baseWidth, baseHeight;
  final int minRows;
}

/// A measured editor viewport, tied to the font used for its cell metrics.
final class EditorViewport {
  const EditorViewport({
    required this.font,
    required this.size,
    required this.cellWidth,
    required this.cellHeight,
    this.origin = Offset.zero,
    this.baseline = 0,
    this.devicePixelRatio = 1,
  });

  final EditorFont font;
  final Size size;
  final Offset origin;
  final double cellWidth;
  final double cellHeight;
  final double baseline, devicePixelRatio;

  int get columns => math.max(1, (size.width / cellWidth + 1e-7).floor());
  int get rows => math.max(1, (size.height / cellHeight + 1e-7).floor());

  Rect previewRect(DisplayWindow window, DisplayGrid grid) => Rect.fromLTWH(
    origin.dx + (grid.col + window.left) * cellWidth,
    origin.dy + (grid.row + window.top) * cellHeight,
    window.width * cellWidth,
    window.height * cellHeight,
  );
}

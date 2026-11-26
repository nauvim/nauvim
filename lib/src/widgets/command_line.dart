import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../headless/editor_model.dart';
import '../headless/protocol.dart';
import '../headless/text_input.dart';
import 'paint_style.dart';
import 'text.dart';

/// Carries the painted prompt's metrics at its caret anchor.
class CommandLineCaret extends SizedBox {
  const CommandLineCaret({
    required super.key,
    required this.baseline,
    required this.style,
  });

  final double baseline;
  final TextStyle style;
}

class CommandLine extends StatefulWidget {
  const CommandLine({
    super.key,
    required this.item,
    required this.model,
    required this.style,
    required this.active,
    this.caretKey,
    this.composingKey,
    this.preedit,
    this.popupLink,
    this.popupByteOffset,
    this.popupWidth = 480,
    this.cursorColor,
    this.cursorWidth = 2,
    this.paintStyle = const EditorPaintStyle(),
  });
  final DisplayWidget item;
  final EditorModel model;
  final TextStyle style;
  final bool active;
  final GlobalKey? caretKey;
  final GlobalKey? composingKey;
  final ValueListenable<EditorPreedit?>? preedit;
  final LayerLink? popupLink;
  final int? popupByteOffset;
  final double popupWidth;
  final Color? cursorColor;
  final double cursorWidth;
  final EditorPaintStyle paintStyle;

  @override
  State<CommandLine> createState() => _CommandLineState();
}

class _CommandLineState extends State<CommandLine> {
  final _scroll = ScrollController();
  (String, int, TextStyle, double, bool)? _followKey;
  int _scrollRevision = 0;

  void followCursor(double caret, double contentWidth, double viewportWidth) {
    final revision = ++_scrollRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _scrollRevision || !_scroll.hasClients) {
        return;
      }
      final offset = _scroll.offset;
      final desired = caret < offset
          ? caret
          : math.max(offset, caret + 3 - viewportWidth);
      final maxExtent = math.max(0.0, contentWidth - viewportWidth);
      final target = desired.clamp(0.0, maxExtent).toDouble();
      if (target != offset) {
        _scroll.jumpTo(target);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preedit = widget.preedit;
    if (preedit == null || !widget.active) return _buildLine(context, null);
    return ValueListenableBuilder(
      valueListenable: preedit,
      builder: (context, draft, _) => _buildLine(context, draft),
    );
  }

  Widget _buildLine(BuildContext context, EditorPreedit? draft) {
    final text = widget.item.chunks.map((c) => c.text).join();
    final insertion = byteOffsetToUtf16(text, widget.item.selected);
    final composition = draft != null && draft.text.isNotEmpty
        ? _Composition(
            insertion,
            draft.text.length,
            TextSelection(
              baseOffset: draft.selectionStart,
              extentOffset: draft.selectionEnd,
            ),
            draft.segments,
          )
        : null;
    final chunks = composition == null
        ? null
        : _insertDraft(widget.item.chunks, insertion, draft!.text);
    final painter = widgetTextPainter(
      widget.item,
      widget.model,
      widget.style,
      paintStyle: widget.paintStyle,
      chunks: chunks,
    );
    final size = painter.size;
    Offset position(int offset) =>
        painter.getOffsetForCaret(TextPosition(offset: offset), Rect.zero);
    final caret = position(insertion);
    final caretHeight = painter.preferredLineHeight;
    final caretBaseline =
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic) -
        caret.dy;
    final popupOffset = byteOffsetToUtf16(
      text,
      widget.popupByteOffset ?? widget.item.selected,
    );
    final popup = position(
      popupOffset + (popupOffset > insertion ? composition?.length ?? 0 : 0),
    ).dx;
    final followOffset = composition?.cursorOffset ?? insertion;
    final follow = position(followOffset).dx;
    final composingBounds = composition?.bounds(painter);
    painter.dispose();
    final visibleText = chunks?.map((c) => c.text).join() ?? text;
    return Semantics(
      label: visibleText,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : size.width + 3;
          final key = (
            visibleText,
            followOffset,
            widget.style,
            viewportWidth,
            widget.active,
          );
          if (key != _followKey) {
            _followKey = key;
            if (widget.active) {
              followCursor(follow, size.width + 3, viewportWidth);
            }
          }
          return SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: size.width + 3,
              height: size.height,
              child: AnimatedBuilder(
                animation: _scroll,
                child: CustomPaint(
                  painter: _CommandLinePainter(
                    widget.item,
                    widget.model,
                    widget.style,
                    widget.active,
                    widget.cursorColor,
                    widget.cursorWidth,
                    widget.paintStyle,
                    insertion,
                    chunks,
                    composition,
                    1 / View.of(context).devicePixelRatio,
                  ),
                ),
                builder: (context, child) {
                  final offset = _scroll.hasClients ? _scroll.offset : 0.0;
                  final anchor = popup.clamp(
                    offset,
                    offset + math.max(0.0, viewportWidth - widget.popupWidth),
                  );
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: child!),
                      if (widget.caretKey case final key? when widget.active)
                        Positioned(
                          left: caret.dx,
                          top: caret.dy,
                          width: widget.cursorWidth,
                          height: caretHeight,
                          child: CommandLineCaret(
                            key: key,
                            baseline: caretBaseline,
                            style: widget.style,
                          ),
                        ),
                      if (widget.composingKey case final key?
                          when composingBounds != null)
                        Positioned.fromRect(
                          rect: composingBounds,
                          child: SizedBox(key: key),
                        ),
                      if (widget.popupLink case final link?)
                        Positioned(
                          left: anchor,
                          top: 0,
                          width: 0,
                          height: 0,
                          child: CompositedTransformTarget(
                            link: link,
                            child: const SizedBox.shrink(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

List<DisplayChunk> _insertDraft(
  List<DisplayChunk> chunks,
  int offset,
  String draft,
) {
  var remaining = offset;
  for (var i = 0; i < chunks.length; i++) {
    final chunk = chunks[i];
    if (remaining > chunk.text.length) {
      remaining -= chunk.text.length;
      continue;
    }

    return [
      ...chunks.take(i),
      DisplayChunk(
        text: chunk.text.replaceRange(remaining, remaining, draft),
        highlight: chunk.highlight,
      ),
      ...chunks.skip(i + 1),
    ];
  }
  return [...chunks, DisplayChunk(text: draft, highlight: 0)];
}

class _Composition {
  const _Composition(this.start, this.length, this.selection, this.segments);

  final int start;
  final int length;
  final TextSelection selection;
  final List<EditorPreeditSegment> segments;

  bool get hasSelection => selection.isValid && selection.end <= length;
  int get cursorOffset =>
      start + (hasSelection ? selection.extentOffset : length);

  TextSelection get range =>
      TextSelection(baseOffset: start, extentOffset: start + length);

  Rect? bounds(TextPainter painter) {
    Rect? bounds;
    for (final box in painter.getBoxesForSelection(range)) {
      final rect = box.toRect();
      bounds = bounds?.expandToInclude(rect) ?? rect;
    }
    return bounds;
  }

  void paint(
    Canvas canvas,
    TextPainter painter,
    Size size,
    Paint ink,
    double pixel,
  ) {
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final bottom = math.min(size.height, baseline + 3 * pixel);
    void underline(TextSelection selection, double thickness) {
      for (final box in painter.getBoxesForSelection(selection)) {
        canvas.drawRect(
          Rect.fromLTRB(box.left, bottom - thickness, box.right, bottom),
          ink,
        );
      }
    }

    underline(range, pixel);
    for (final segment in segments) {
      final marked = TextSelection(
        baseOffset: start + segment.start,
        extentOffset: start + segment.end,
      );
      underline(marked, (segment.selected ? 3 : 2) * pixel);
      if (segment.end < length) {
        final edge = painter.getOffsetForCaret(
          TextPosition(offset: start + segment.end),
          Rect.zero,
        );
        canvas.drawRect(
          Rect.fromLTRB(edge.dx - pixel, bottom - 4 * pixel, edge.dx, bottom),
          ink,
        );
      }
    }
    if (!hasSelection) return;
    if (!selection.isCollapsed) {
      underline(
        TextSelection(
          baseOffset: start + selection.start,
          extentOffset: start + selection.end,
        ),
        2 * pixel,
      );
    } else {
      final caret = painter.getOffsetForCaret(
        TextPosition(offset: cursorOffset, affinity: selection.affinity),
        Rect.zero,
      );
      canvas.drawRect(
        Rect.fromLTRB(
          caret.dx,
          math.max(0, baseline - 4 * pixel),
          caret.dx + pixel,
          bottom,
        ),
        ink,
      );
    }
  }
}

class _CommandLinePainter extends CustomPainter {
  const _CommandLinePainter(
    this.item,
    this.model,
    this.style,
    this.active,
    this.cursorColor,
    this.cursorWidth,
    this.paintStyle,
    this.insertion,
    this.chunks,
    this.composition,
    this.pixel,
  );
  final DisplayWidget item;
  final EditorModel model;
  final TextStyle style;
  final bool active;
  final Color? cursorColor;
  final double cursorWidth;
  final EditorPaintStyle paintStyle;
  final int insertion;
  final List<DisplayChunk>? chunks;
  final _Composition? composition;
  final double pixel;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = widgetTextPainter(
      item,
      model,
      style,
      paintStyle: paintStyle,
      chunks: chunks,
    );
    painter.paint(canvas, Offset.zero);
    final composing = composition;
    final foreground = paintStyle.resolveForeground(model.frame?.foreground);
    if (composing != null) {
      composing.paint(
        canvas,
        painter,
        size,
        Paint()..color = foreground,
        pixel,
      );
    } else if (active) {
      final cursor = painter.getOffsetForCaret(
        TextPosition(offset: insertion),
        Rect.zero,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          cursor.dx,
          cursor.dy,
          cursorWidth,
          painter.preferredLineHeight,
        ),
        Paint()..color = cursorColor ?? foreground,
      );
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(_CommandLinePainter oldDelegate) => true;
}

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../headless/editor_model.dart';
import '../headless/protocol.dart';
import 'text.dart';
import 'paint_style.dart';

class CommandLine extends StatefulWidget {
  const CommandLine({
    super.key,
    required this.item,
    required this.model,
    required this.style,
    required this.active,
    this.caretKey,
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
    final text = widget.item.chunks.map((c) => c.text).join();
    final painter = widgetTextPainter(
      widget.item,
      widget.model,
      widget.style,
      paintStyle: widget.paintStyle,
    );
    final size = painter.size;
    Offset position(int byteOffset) => painter.getOffsetForCaret(
      TextPosition(offset: byteOffsetToUtf16(text, byteOffset)),
      Rect.zero,
    );
    final caret = position(widget.item.selected);
    final caretHeight = painter.preferredLineHeight;
    final popup = position(widget.popupByteOffset ?? widget.item.selected).dx;
    painter.dispose();
    return Semantics(
      label: text,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : size.width + 3;
          final key = (
            text,
            widget.item.selected,
            widget.style,
            viewportWidth,
            widget.active,
          );
          if (key != _followKey) {
            _followKey = key;
            if (widget.active) {
              followCursor(caret.dx, size.width + 3, viewportWidth);
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

class _CommandLinePainter extends CustomPainter {
  const _CommandLinePainter(
    this.item,
    this.model,
    this.style,
    this.active,
    this.cursorColor,
    this.cursorWidth,
    this.paintStyle,
  );
  final DisplayWidget item;
  final EditorModel model;
  final TextStyle style;
  final bool active;
  final Color? cursorColor;
  final double cursorWidth;
  final EditorPaintStyle paintStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = widgetTextPainter(
      item,
      model,
      style,
      paintStyle: paintStyle,
    );
    painter.paint(canvas, Offset.zero);
    if (active) {
      final text = item.chunks.map((c) => c.text).join();
      final cursor = painter.getOffsetForCaret(
        TextPosition(offset: byteOffsetToUtf16(text, item.selected)),
        Rect.zero,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          cursor.dx,
          cursor.dy,
          cursorWidth,
          painter.preferredLineHeight,
        ),
        Paint()
          ..color =
              cursorColor ??
              paintStyle.resolveForeground(model.frame?.foreground),
      );
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(_CommandLinePainter oldDelegate) => true;
}

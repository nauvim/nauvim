import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../headless/controller.dart';
import '../headless/viewport.dart';
import 'editor_viewport.dart';
import 'grid_renderer.dart';
import 'keyboard.dart';
import 'paint_style.dart';

/// An unstyled Neovim canvas with keyboard and grid-local selection behavior.
class EditorSurface extends StatefulWidget {
  const EditorSurface({
    super.key,
    required this.controller,
    required this.style,
    this.overlayBuilder,
    this.autofocus = true,
    this.metrics = const EditorMetricsStyle(),
    this.viewport,
  });

  final NauvimController controller;
  final EditorPaintStyle style;
  final List<Widget> Function(BuildContext, EditorViewport)? overlayBuilder;
  final bool autofocus;
  final EditorMetricsStyle metrics;
  final EditorViewport? viewport;

  @override
  State<EditorSurface> createState() => _EditorSurfaceState();
}

class _EditorSurfaceState extends State<EditorSurface> {
  final _renderer = GridRenderer();
  final _focus = FocusNode();
  bool _attached = false;

  @override
  void initState() {
    super.initState();
    _attached = widget.controller.attached;
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(EditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_controllerChanged);
    widget.controller.addListener(_controllerChanged);
    _attached = widget.controller.attached;
    _renderer.dispose();
  }

  void _controllerChanged() {
    final attached = widget.controller.attached;
    if (attached && !_attached && widget.autofocus) _focus.requestFocus();
    _attached = attached;
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    final controller = widget.controller;
    if (!controller.attached || controller.closing) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final shortcut = defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed &&
              !keyboard.isShiftPressed &&
              !keyboard.isAltPressed &&
              !keyboard.isControlPressed
        : keyboard.isControlPressed &&
              keyboard.isShiftPressed &&
              !keyboard.isAltPressed &&
              !keyboard.isMetaPressed;
    if (shortcut && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (event is KeyDownEvent) unawaited(controller.paste());
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        shortcut &&
        event.logicalKey == LogicalKeyboardKey.keyC &&
        controller.editor.selectionStart != null) {
      unawaited(controller.copySelection());
      return KeyEventResult.handled;
    }
    final keys = encodeKey(event);
    if (keys == null) return KeyEventResult.ignored;
    unawaited(controller.sendKeys(keys));
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _renderer.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: widget.autofocus && widget.controller.attached,
    onKeyEvent: _key,
    child: switch (widget.viewport) {
      final viewport? => _canvas(context, viewport),
      null => EditorViewportRegion(
        controller: widget.controller,
        metrics: widget.metrics,
        builder: _canvas,
      ),
    },
  );

  Widget _canvas(BuildContext context, EditorViewport viewport) {
    final model = widget.controller.editor;
    final font = viewport.font;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              _focus.requestFocus();
              final point = model.hit(
                details.localPosition.dx,
                details.localPosition.dy,
                viewport.cellWidth,
                viewport.cellHeight,
              );
              if (point != null) model.beginSelection(point);
            },
            onPanUpdate: (details) {
              final point = model.hit(
                details.localPosition.dx,
                details.localPosition.dy,
                viewport.cellWidth,
                viewport.cellHeight,
              );
              if (point != null) model.extendSelection(point);
            },
            onTapDown: (_) {
              _focus.requestFocus();
              model.clearSelection();
            },
            child: RepaintBoundary(
              child: CustomPaint(
                painter: EditorPainter(
                  model,
                  _renderer,
                  font.families.first,
                  font.families.skip(1).toList(),
                  font.size,
                  viewport.cellWidth,
                  viewport.cellHeight,
                  style: widget.style,
                  fonts: font,
                  baseline: viewport.baseline > 0 ? viewport.baseline : null,
                ),
              ),
            ),
          ),
        ),
        ...?widget.overlayBuilder?.call(context, viewport),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../headless/controller.dart';
import '../headless/key_bindings.dart';
import '../headless/protocol.dart';
import '../headless/viewport.dart';
import 'command_line.dart';
import 'editor_text_input.dart';
import 'editor_viewport.dart';
import 'grid_renderer.dart';
import 'ime_overlay.dart';
import 'keyboard.dart';
import 'paint_style.dart';
import 'text.dart';

typedef _ImeCaret = ({
  Rect rect,
  double baseline,
  TextStyle? promptStyle,
  EditorFont font,
});

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
    this.commandLineCaretKey,
  });

  final NauvimController controller;
  final EditorPaintStyle style;
  final List<Widget> Function(BuildContext, EditorViewport)? overlayBuilder;
  final bool autofocus;
  final EditorMetricsStyle metrics;
  final EditorViewport? viewport;

  /// The caret marker of an active, separately rendered command line.
  final GlobalKey? commandLineCaretKey;

  @override
  State<EditorSurface> createState() => _EditorSurfaceState();
}

class _EditorSurfaceState extends State<EditorSurface>
    with WidgetsBindingObserver {
  final _renderer = GridRenderer();
  final _focus = FocusNode();
  final _canvasKey = GlobalKey();
  final _preeditKey = GlobalKey();
  final _imeOverlay = OverlayPortalController();
  bool _attached = false;
  bool _imeRequested = false;
  bool _geometryPending = false;
  EditorTextInput? _textInput;
  int? _textAttachment;
  EditorPreedit? _preedit;
  _ImeCaret? _imeCaret;
  EditorViewport? _paintedViewport;

  @override
  void initState() {
    super.initState();
    _attached = widget.controller.attached;
    _imeRequested = widget.controller.nativeTextInput;
    _focus.addListener(_syncTextInput);
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(EditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_controllerChanged);
    widget.controller.addListener(_controllerChanged);
    _closeTextInput();
    _renderer.dispose();
    _controllerChanged();
  }

  void _controllerChanged() {
    final controller = widget.controller;
    final attached = controller.attached;
    final imeRequested = controller.nativeTextInput;
    if (attached &&
        ((!_attached && widget.autofocus) || imeRequested != _imeRequested)) {
      _focus.requestFocus();
    }
    _attached = attached;
    _imeRequested = imeRequested;
    _syncTextInput();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncTextInput();

  void _syncTextInput() {
    final controller = widget.controller;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!controller.attached ||
        controller.closing ||
        !controller.nativeTextInput ||
        !_focus.hasPrimaryFocus ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      _closeTextInput();
      return;
    }

    final attachment = controller.attachmentGeneration;
    if (_textInput?.attached == true && _textAttachment == attachment) return;

    _closeTextInput();
    late final EditorTextInput input;
    input = EditorTextInput(
      onPreedit: (preedit) {
        if (identical(_textInput, input)) _updatePreedit(preedit);
      },
      onCommit: (text) {
        if (identical(_textInput, input)) {
          unawaited(controller.sendText(text, attachment: attachment));
        }
      },
      onClosed: () {
        if (identical(_textInput, input)) {
          _closeTextInput();
          controller.setNativeTextInput(false);
        }
      },
    );
    _textInput = input;
    _textAttachment = attachment;
    input.open(View.of(context).viewId);
    _scheduleTextInputGeometry();
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _closeTextInput() {
    final input = _textInput;
    if (input == null) return;
    _textInput = null;
    _textAttachment = null;
    _imeCaret = null;
    _updatePreedit(null);
    input.close();
  }

  void _updatePreedit(EditorPreedit? preedit) {
    if (preedit == _preedit) return;
    setState(() => _preedit = preedit);
    if (preedit == null) {
      _imeOverlay.hide();
    } else {
      _imeOverlay.show();
    }
  }

  void _scheduleTextInputGeometry() {
    if (_geometryPending || _textInput == null) return;
    _geometryPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryPending = false;
      final input = _textInput;
      if (!mounted || input == null) return;
      _updateTextInputGeometry(input);
      // An active session follows render updates, including scrolling. A
      // post-frame callback does not request an additional frame by itself.
      _scheduleTextInputGeometry();
    });
  }

  _ImeCaret? _visibleCaret() {
    final viewport = _paintedViewport;
    if (viewport == null) return null;

    final commandLine = widget.commandLineCaretKey;
    if (commandLine != null && commandLine.currentContext != null) {
      final rect = imeCommandLineCaret(commandLine);
      final box = commandLine.currentContext?.findRenderObject();
      if (rect == null || box is! RenderBox) return null;
      final marker = commandLine.currentWidget;
      final baseline = marker is CommandLineCaret
          ? marker.baseline
          : _gridBaseline(viewport);
      return (
        rect: rect,
        baseline: box.localToGlobal(Offset(0, baseline)).dy - rect.top,
        promptStyle: marker is CommandLineCaret ? marker.style : null,
        font: viewport.font,
      );
    }

    final box = _canvasKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final cell = imeGridCaret(widget.controller.editor, viewport);
    if (cell == null) return null;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      cell.intersect(Offset.zero & viewport.size),
    );
    final baseline = cell.top + _gridBaseline(viewport);
    return (
      rect: rect,
      baseline: box.localToGlobal(Offset(cell.left, baseline)).dy - rect.top,
      promptStyle: null,
      font: viewport.font,
    );
  }

  double _gridBaseline(EditorViewport viewport) => viewport.baseline > 0
      ? viewport.baseline
      : gridAlphabeticBaseline(
          viewport.font.families.first,
          viewport.font.families.skip(1).toList(),
          viewport.font.size,
          viewport.cellHeight,
        );

  void _updateTextInputGeometry(EditorTextInput input) {
    final caret = _visibleCaret();
    final moved = caret != _imeCaret;
    if (moved && _preedit != null) {
      setState(() => _imeCaret = caret);
    } else {
      _imeCaret = caret;
    }
    if (caret == null || !caret.rect.isFinite) return;

    final box = _preeditKey.currentContext?.findRenderObject();
    final composing = !moved && box is RenderBox && box.hasSize
        ? MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          )
        : null;
    final rect = caret.rect;
    final anchor = Rect.fromLTWH(rect.left, rect.top, 1, rect.height);
    final view = View.of(context);
    input.updateGeometry(
      view.physicalSize / view.devicePixelRatio,
      anchor,
      composing != null && composing.isFinite && !composing.isEmpty
          ? composing
          : anchor,
    );
  }

  Widget _buildPreedit(BuildContext context) {
    final caret = _imeCaret;
    final preedit = _preedit;
    if (caret == null || preedit == null) return const SizedBox.shrink();

    final controller = widget.controller;
    final font = caret.font;
    final frame = controller.editor.frame;
    final foreground = widget.style.resolveForeground(frame?.foreground);
    final textStyle =
        caret.promptStyle ??
        editorTextStyle(
          font.families,
          font.size,
          lineHeight: null,
          variations: font.faces.first.variations,
        );
    final overlay = Overlay.of(context, rootOverlay: true);
    final box = overlay.context.findRenderObject();
    final position = box is RenderBox
        ? box.globalToLocal(caret.rect.topLeft)
        : caret.rect.topLeft;
    return Stack(
      children: [
        Positioned(
          left: position.dx,
          top: position.dy,
          right: 0,
          child: Align(
            alignment: Alignment.topLeft,
            child: ImePreedit(
              key: _preeditKey,
              text: preedit.text,
              selection: preedit.selection,
              baseline: caret.baseline,
              lineHeight: caret.rect.height,
              style: textStyle.copyWith(
                color: textStyle.foreground == null ? foreground : null,
              ),
              spans: caret.promptStyle == null
                  ? gridPreeditSpans(preedit.text, font)
                  : null,
              background: widget.style.resolveBackground(frame?.background),
            ),
          ),
        ),
      ],
    );
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    final controller = widget.controller;
    if (!controller.attached || controller.closing) {
      return KeyEventResult.ignored;
    }
    if (_textInput?.attached == true) {
      return KeyEventResult.skipRemainingHandlers;
    }
    final action = boundKey(
      controller.keyBindings,
      KeyContext.clipboard,
      event,
    );
    if (action == KeyAction.paste) {
      if (event is KeyDownEvent) unawaited(controller.paste());
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        action == KeyAction.copy &&
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
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_controllerChanged);
    _focus.removeListener(_syncTextInput);
    _textInput?.close();
    _textInput = null;
    _renderer.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = Focus(
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
    if (Overlay.maybeOf(context, rootOverlay: true) == null) return surface;
    return OverlayPortal(
      controller: _imeOverlay,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: _buildPreedit,
      child: surface,
    );
  }

  Widget _canvas(BuildContext context, EditorViewport viewport) {
    _paintedViewport = viewport;
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
                key: _canvasKey,
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

import 'dart:async';

import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../headless/controller.dart';
import '../headless/key_bindings.dart';
import '../headless/protocol.dart';
import '../headless/viewport.dart';
import 'editor_text_input.dart';
import 'editor_viewport.dart';
import 'grid_renderer.dart';
import 'grid_preedit.dart';
import 'ime_geometry.dart';
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
    this.commandLineCaretKey,
    this.commandLineComposingKey,
    this.commandLinePreedit,
  });

  final NauvimController controller;
  final EditorPaintStyle style;
  final List<Widget> Function(BuildContext, EditorViewport)? overlayBuilder;
  final bool autofocus;
  final EditorMetricsStyle metrics;
  final EditorViewport? viewport;

  /// The caret marker of an active, separately rendered command line.
  final GlobalKey? commandLineCaretKey;

  /// The composing bounds of the active command line, when it displays preedit.
  final GlobalKey? commandLineComposingKey;

  /// Shares the native preedit with the separately rendered active command line.
  final ValueNotifier<EditorPreedit?>? commandLinePreedit;

  @override
  State<EditorSurface> createState() => _EditorSurfaceState();
}

class _EditorSurfaceState extends State<EditorSurface>
    with WidgetsBindingObserver {
  final _renderer = GridRenderer();
  final _focus = FocusNode();
  final _canvasKey = GlobalKey();
  bool _attached = false;
  bool _imeRequested = false;
  bool _geometryPending = false;
  EditorTextInput? _textInput;
  int? _textAttachment;
  EditorPreedit? _preedit;
  GridPreedit? _gridPreedit;
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
    _updatePreedit(null);
    input.close();
  }

  void _updatePreedit(EditorPreedit? preedit) {
    if (preedit == _preedit) return;
    setState(() {
      _preedit = preedit;
      _gridPreedit = preedit == null ? null : GridPreedit(preedit);
    });
    final target = widget.commandLinePreedit;
    if (target == null) return;
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) {
        if (mounted && identical(widget.commandLinePreedit, target)) {
          target.value = _preedit;
        }
      });
    } else {
      target.value = preedit;
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

  ({Rect caret, Rect? composing})? _visibleInputGeometry() {
    final viewport = _paintedViewport;
    if (viewport == null) return null;

    final commandLine = widget.commandLineCaretKey;
    if (commandLine != null && commandLine.currentContext != null) {
      final mark = widget.commandLineComposingKey;
      final composing = mark == null ? null : imeCommandLineCaret(mark);
      final caret = imeCommandLineCaret(commandLine) ?? composing;
      return caret == null ? null : (caret: caret, composing: composing);
    }

    final box = _canvasKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final model = widget.controller.editor;
    final cell = imeGridCaret(model, viewport);
    if (cell == null) return null;
    final transform = box.getTransformTo(null);
    Rect inView(Rect cell) => MatrixUtils.transformRect(
      transform,
      cell.intersect(Offset.zero & viewport.size),
    );
    final draft = _gridPreedit;
    final composing = draft == null
        ? null
        : imeGridCaret(model, viewport, columns: draft.columns);
    return (
      caret: inView(cell),
      composing: composing == null ? null : inView(composing),
    );
  }

  void _updateTextInputGeometry(EditorTextInput input) {
    final geometry = _visibleInputGeometry();
    if (geometry == null || !geometry.caret.isFinite) return;

    final rect = geometry.caret;
    final composing = geometry.composing;
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
    _paintedViewport = viewport;
    final model = widget.controller.editor;
    final font = viewport.font;
    final externalCommandLine =
        widget.commandLinePreedit != null &&
        model.widgets.any((item) => item.kind == 'cmdline');
    final preedit = externalCommandLine ? null : _gridPreedit;
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
              child: Semantics(
                label: preedit?.text,
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
                    preedit: preedit,
                    pixel: 1 / View.of(context).devicePixelRatio,
                  ),
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

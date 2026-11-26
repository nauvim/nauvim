import 'dart:async';

import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../headless/controller.dart';
import '../headless/key_bindings.dart';
import '../headless/protocol.dart';
import '../headless/viewport.dart';
import '../headless/text_input.dart';
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
  bool _geometryPending = false;
  static int _lastTextClient = 0;
  EditorTextInputPlatform? _textInput;
  int? _textClient;
  ({Rect caret, Rect composing})? _lastGeometry;
  int? _textAttachment;
  EditorPreedit? _preedit;
  GridPreedit? _gridPreedit;
  EditorViewport? _paintedViewport;

  @override
  void initState() {
    super.initState();
    _attached = widget.controller.attached;
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
    if (attached && !_attached && widget.autofocus) _focus.requestFocus();
    _attached = attached;
    _syncTextInput();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncTextInput();

  void _syncTextInput() {
    final controller = widget.controller;
    final platform = controller.textInputPlatform;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (platform == null ||
        !controller.attached ||
        controller.closing ||
        !controller.nativeTextInput ||
        !_focus.hasPrimaryFocus ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      _closeTextInput();
      return;
    }

    final attachment = controller.attachmentGeneration;
    if (identical(_textInput, platform) && _textAttachment == attachment) {
      return;
    }

    _closeTextInput();
    final client = ++_lastTextClient;
    _textInput = platform;
    _textClient = client;
    _textAttachment = attachment;
    _nativeOperation(
      'Open native text input',
      platform.openTextInput(client, (event) {
        if (!controller.attached ||
            controller.attachmentGeneration != attachment) {
          return;
        }
        switch (event) {
          case EditorPreedit(:final text):
            if (_textClient == client && _focus.hasPrimaryFocus) {
              _updatePreedit(text.isEmpty ? null : event);
            }
          case EditorTextCommit(:final text):
            if (_textClient == client) _updatePreedit(null);
            unawaited(controller.sendText(text, attachment: attachment));
        }
      }),
    );
    _scheduleTextInputGeometry();
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _closeTextInput({bool repaint = true}) {
    final input = _textInput;
    final client = _textClient;
    if (input == null || client == null) return;
    _textInput = null;
    _textClient = null;
    _textAttachment = null;
    _lastGeometry = null;
    if (repaint) _updatePreedit(null);
    _nativeOperation('Close native text input', input.closeTextInput(client));
  }

  void _nativeOperation(String operation, Future<void> result) {
    final controller = widget.controller;
    unawaited(
      result.catchError((Object error) {
        controller.reportError('$operation: $error');
      }),
    );
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
      if (!mounted) return;
      final input = _textInput;
      final client = _textClient;
      if (input == null || client == null) return;
      _updateTextInputGeometry(input, client);
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

  void _updateTextInputGeometry(EditorTextInputPlatform input, int client) {
    final geometry = _visibleInputGeometry();
    if (geometry == null || !geometry.caret.isFinite) return;

    final rect = geometry.caret;
    final composing = geometry.composing;
    final anchor = Rect.fromLTWH(rect.left, rect.top, 1, rect.height);
    final visible = (
      caret: anchor,
      composing: composing != null && composing.isFinite && !composing.isEmpty
          ? composing
          : anchor,
    );
    if (visible == _lastGeometry) return;
    _lastGeometry = visible;
    _nativeOperation(
      'Position native text input',
      input.updateTextInputGeometry(
        client,
        caret: visible.caret,
        composing: visible.composing,
      ),
    );
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    final controller = widget.controller;
    if (!controller.attached || controller.closing || event.synthesized) {
      return KeyEventResult.ignored;
    }
    // The native runner delivers only keys that the text input system leaves
    // for ordinary handling. With native text input disabled this is every key.
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
    _closeTextInput(repaint: false);
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

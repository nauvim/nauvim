import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'editor_model.dart';
import 'engine.dart';
import 'key_bindings.dart';
import 'platform.dart';
import 'previews.dart';
import 'protocol.dart';
import 'viewport.dart';
import 'window_geometry.dart';

enum _WindowSetup { waiting, cells, applying, done }

/// The application state shared by every visual design.
enum SessionPhase { welcome, connecting, attached, closing }

/// Owns session behavior without creating widgets or selecting an appearance.
///
/// Report a viewport after layout with the exact [font] used to measure its
/// cells. Startup waits for that measurement and font discovery. Subsequent
/// reports update the engine size and place native previews within the grids.
final class NauvimController extends ChangeNotifier {
  NauvimController({
    NauvimEngine? engine,
    required NauvimPlatform platform,
    String? startupError,
    // A runner can wait for configuration even when no window options arrive.
    this._defaultWindowOptions,
  }) : _engine = engine,
       _platform = platform,
       _connectionError = startupError {
    _previews = Previews(platform, editor, reportError);
    _refreshErrors();
    platform.setEventHandler(_platformEvent);
    _subscription = engine?.updates().listen(
      _update,
      onError: _streamError,
      onDone: () {
        _configureDefaultWindow();
        _finishUpdates();
      },
    );
    if (engine == null) _configureDefaultWindow();
  }

  final NauvimEngine? _engine;
  final NauvimPlatform _platform;
  final WindowOptions? _defaultWindowOptions;
  final editor = EditorModel();
  late final Previews _previews;
  final _updatesFinished = Completer<void>();
  StreamSubscription<UiUpdate>? _subscription;
  Future<void> _input = Future.value();
  Future<void>? _closeFuture;
  Future<void>? _initialWindow;
  Timer? _resize;
  bool _disposed = false;
  bool _ready = false;
  bool _started = false;
  bool _nativeTextInput = false;
  _WindowSetup _windowSetup = _WindowSetup.waiting;
  DisplayWindowOptions? _pendingWindow;
  int _attachment = 0;
  int _fontRequest = 0;
  (double, double, double, double, int, Size)? _windowGrid;
  (int, int)? _dimensions;
  EditorViewport? _viewport;
  EditorFont _font = const EditorFont.fallback();
  WindowMargins? _windowMargins;
  SessionPhase _phase = SessionPhase.welcome;
  String _destination = '';
  List<String> _hosts = const [];
  NauvimKeyBindings _keyBindings = NauvimKeyBindings();
  final _diagnostics = <String>[];
  String? _connectionError;
  List<String> _errors = const [];

  SessionPhase get phase => _phase;
  bool get attached => _phase == SessionPhase.attached;
  bool get connecting => _phase == SessionPhase.connecting;
  bool get closing => _phase == SessionPhase.closing;
  bool get ready => _ready && _windowSetup == _WindowSetup.done;
  bool get hasEngine => _engine != null;
  bool get nativeTextInput => _nativeTextInput;

  /// Identifies the attachment that owns queued input and text composition.
  int get attachmentGeneration => _attachment;

  String get destination => _destination;
  List<String> get hosts => _hosts;
  NauvimKeyBindings get keyBindings => _keyBindings;
  EditorFont get font => _font;
  EditorViewport? get viewport => _viewport;
  WindowMargins? get windowMargins => _windowMargins;
  List<String> get errors => _errors;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _refreshErrors() {
    _errors = List.unmodifiable([
      ..._diagnostics,
      if (_connectionError case final message?)
        if (!_diagnostics.contains(message)) message,
    ]);
  }

  void reportError(String message) {
    if (_disposed || _diagnostics.contains(message)) return;
    if (_diagnostics.length == 100) _diagnostics.removeAt(0);
    _diagnostics.add(message);
    _refreshErrors();
    _changed();
  }

  void dismissErrors() {
    if (_errors.isEmpty || _disposed) return;
    _diagnostics.clear();
    _connectionError = null;
    _refreshErrors();
    _changed();
  }

  Future<void> _guard(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (e) {
      reportError(e.toString());
    }
  }

  Future<void> _platformEvent(NauvimPlatformEvent event) async {
    switch (event) {
      case WindowCloseRequested():
        await close();
      case WindowSizeChanged(:final width, :final height):
        if (_engine case final WindowSizeRecorder recorder when !closing) {
          recorder.recordWindowSize(width: width, height: height);
        }
      case PlatformFailure(:final message):
        reportError(message);
      case PreviewCloseRequested(:final handle):
        _previews.clear(handle, userRequested: true);
      case PreviewNavigationRequested(:final handle, :final url):
        await _guard(() async {
          event.allowed = await _previews.allowsNavigation(handle, url);
        });
      case PreviewFocusRequested(:final handle):
        await _guard(() async {
          event.allowed = await _previews.canFocus(handle);
        });
      case PreviewFailure(:final handle, :final message):
        await _guard(() => _previews.reportFailure(handle, message));
    }
  }

  void _finishUpdates() {
    if (!_updatesFinished.isCompleted) _updatesFinished.complete();
  }

  void _streamError(Object error) {
    if (_disposed) return;
    _finishUpdates();
    _resetAttachment();
    if (!closing) _phase = SessionPhase.welcome;
    _connectionError = error.toString();
    _refreshErrors();
    _changed();
    _configureDefaultWindow();
  }

  void _configureDefaultWindow() {
    if (_disposed || closing || _windowSetup != _WindowSetup.waiting) return;
    if (_defaultWindowOptions case final options?) {
      _initialWindow = _applyWindow(options);
    } else {
      _windowSetup = _WindowSetup.done;
    }
  }

  Future<void> _configureFonts(
    List<DisplayFont> fonts,
    DisplayWindowOptions? windowOptions,
  ) async {
    final request = ++_fontRequest;
    if (_windowSetup == _WindowSetup.waiting) {
      if (windowOptions == null) {
        _configureDefaultWindow();
      } else if (windowUsesCells(windowOptions)) {
        _pendingWindow = windowOptions;
        _windowSetup = _WindowSetup.cells;
      } else {
        _initialWindow = _configureWindow(windowOptions);
      }
    }
    await _initialWindow;
    if (_disposed || closing || request != _fontRequest) return;
    final EditorFont resolved;
    try {
      resolved = await _platform.resolveFonts(
        fonts.isEmpty
            ? const [DisplayFont(family: 'monospace', size: 15)]
            : fonts,
      );
    } catch (e) {
      if (!_disposed && !closing && request == _fontRequest) {
        reportError('Find configured fonts: $e');
        if (_pendingWindow case final options?) {
          _initialWindow = _applyWindow(_windowAppearance(options));
          await _initialWindow;
        }
      }
      return;
    }
    if (_disposed || closing || request != _fontRequest) return;
    _font = resolved;
    _ready = true;
    _changed();
    _startIfMeasured();
  }

  Future<void> _configureWindow(
    DisplayWindowOptions options, {
    double? cellWidth,
    double? cellHeight,
  }) {
    final WindowOptions resolved;
    try {
      resolved = WindowOptions.resolve(
        options,
        cellWidth: cellWidth,
        cellHeight: cellHeight,
      );
    } catch (e) {
      final applied = _applyWindow(_windowAppearance(options));
      reportError('Resolve window geometry: $e');
      return applied;
    }
    return _applyWindow(resolved);
  }

  WindowOptions _windowAppearance(DisplayWindowOptions options) =>
      WindowOptions(
        decorations: options.decorations,
        opacity: options.opacity,
        startupMode: options.startupMode,
      );

  Future<void> _applyWindow(WindowOptions options) async {
    _windowSetup = _WindowSetup.applying;
    _pendingWindow = null;
    _windowMargins = options.margin;
    await _guard(() => _platform.configureInitialWindow(options));
    _windowSetup = _WindowSetup.done;
    _changed();
  }

  bool _windowReady(double cellWidth, double cellHeight) {
    if (_windowSetup == _WindowSetup.cells) {
      _initialWindow = _configureWindow(
        _pendingWindow!,
        cellWidth: cellWidth,
        cellHeight: cellHeight,
      );
    }
    return _windowSetup == _WindowSetup.done;
  }

  /// Reports native resize hints and, with a matching [font], startup cell sizes.
  void updateWindowGrid(WindowGrid grid, Size windowSize, {EditorFont? font}) {
    if (_disposed || closing || !_ready) return;
    if (_windowSetup == _WindowSetup.cells && !identical(font, _font)) return;
    if (!_windowReady(grid.cellWidth, grid.cellHeight)) return;
    final key = (
      grid.cellWidth,
      grid.cellHeight,
      grid.baseWidth,
      grid.baseHeight,
      grid.minRows,
      windowSize,
    );
    if (_windowGrid == key) return;
    _windowGrid = key;
    unawaited(_guard(() => _platform.configureWindowGrid(grid)));
  }

  void _update(UiUpdate update) {
    if (_disposed) return;
    switch (update.kind) {
      case 'ready':
        if (closing) return;
        _hosts = List.unmodifiable(update.hosts);
        _keyBindings = NauvimKeyBindings(update.keyBindings);
        _previews.keyBindings = _keyBindings.bindings(KeyContext.webview);
        if (!_started) _destination = update.destination?.alias ?? '';
        _changed();
        unawaited(_configureFonts(update.fonts, update.windowOptions));
      case 'connecting':
        if (closing) return;
        _resetAttachment();
        _phase = SessionPhase.connecting;
        _destination = switch (update.destination) {
          DisplayDestination(:final alias) => alias ?? '',
          null => update.message ?? '',
        };
        _changed();
      case 'frame':
        if (closing) return;
        final frame = update.frame;
        if (frame == null) return;
        final wasAttached = attached;
        _phase = SessionPhase.attached;
        _previews.invalidateLayout();
        editor.apply(frame);
        if (!wasAttached) {
          _connectionError = null;
          _refreshErrors();
          _changed();
        }
        for (final event in frame.events) {
          switch (event.kind) {
            case 'error':
              reportError(event.text);
            case 'bell' || 'visual_bell':
              unawaited(_guard(_platform.alert));
            case 'title':
              unawaited(_guard(() => _platform.setTitle(event.text)));
          }
        }
      case 'welcome':
        if (closing) return;
        _resetAttachment();
        _phase = SessionPhase.welcome;
        _connectionError = update.message;
        _refreshErrors();
        _changed();
      case 'error':
        if (update.message case final message?) reportError(message);
      case 'open_webview':
        final window = update.window;
        if (!closing && window != null) _previews.open(window);
      case 'close_webview':
        if (update.window case final window?) _previews.clear(window.handle);
      case 'focus_webview':
        if (update.window case final window? when !closing) {
          _previews.focus(window.handle);
        }
      case 'navigate_webview':
        if (update.window case final window? when !closing) {
          unawaited(_guard(() => _previews.navigate(window)));
        }
      case 'shutdown':
        _finishUpdates();
        unawaited(close());
    }
  }

  void _resetAttachment() {
    _attachment++;
    _nativeTextInput = false;
    _previews.reset();
    editor.clear();
  }

  /// Reports the editor's actual, post-layout geometry.
  void updateViewport(EditorViewport viewport) {
    if (_disposed || closing || !identical(viewport.font, _font)) return;
    // The engine bridge represents cell counts as unsigned 32-bit values.
    final columns = viewport.size.width / viewport.cellWidth;
    final rows = viewport.size.height / viewport.cellHeight;
    if (!columns.isFinite ||
        !rows.isFinite ||
        columns > 0xffffffff ||
        rows > 0xffffffff ||
        !viewport.cellWidth.isFinite ||
        !viewport.cellHeight.isFinite ||
        viewport.cellWidth <= 0 ||
        viewport.cellHeight <= 0 ||
        !viewport.size.width.isFinite ||
        !viewport.size.height.isFinite ||
        viewport.size.width < 0 ||
        viewport.size.height < 0) {
      reportError('Measure editor viewport: invalid dimensions');
      return;
    }
    if (_windowSetup == _WindowSetup.cells && !_ready) return;
    if (_ready && !_windowReady(viewport.cellWidth, viewport.cellHeight)) {
      return;
    }
    _viewport = viewport;
    _previews.layout(viewport, attached: attached);
    final dimensions = (viewport.columns, viewport.rows);
    if (!_started) {
      _startIfMeasured();
      return;
    }
    if (_dimensions == dimensions) return;
    _dimensions = dimensions;
    _resize?.cancel();
    _resize = Timer(const Duration(milliseconds: 40), () {
      final engine = _engine;
      if (!_disposed && !closing && engine != null) {
        unawaited(
          _guard(
            () => engine.resize(width: dimensions.$1, height: dimensions.$2),
          ),
        );
      }
    });
  }

  void _startIfMeasured() {
    final viewport = _viewport;
    final engine = _engine;
    if (_disposed ||
        closing ||
        !_ready ||
        _windowSetup != _WindowSetup.done ||
        _started ||
        viewport == null ||
        engine == null ||
        !identical(viewport.font, _font)) {
      return;
    }
    _started = true;
    _dimensions = (viewport.columns, viewport.rows);
    unawaited(
      _guard(
        () => engine.start(width: viewport.columns, height: viewport.rows),
      ),
    );
  }

  Future<void> connect(String host) => _connect(host);
  Future<void> connectDefault() => _connect(null);

  Future<void> _connect(String? host) async {
    final engine = _engine;
    if (_disposed ||
        closing ||
        connecting ||
        engine == null ||
        (host != null && host.trim().isEmpty)) {
      return;
    }
    _started = true;
    _resize?.cancel();
    _resetAttachment();
    _phase = SessionPhase.connecting;
    _destination = host ?? '';
    _connectionError = null;
    _refreshErrors();
    final dimensions = _viewport == null
        ? (100, 30)
        : (_viewport!.columns, _viewport!.rows);
    _dimensions = dimensions;
    _changed();
    await _guard(
      () => host == null
          ? engine.connectDefault(width: dimensions.$1, height: dimensions.$2)
          : engine.connect(
              host: host,
              width: dimensions.$1,
              height: dimensions.$2,
            ),
    );
  }

  Future<void> detach() async {
    final engine = _engine;
    if (!_disposed && !closing && engine != null) await _guard(engine.detach);
  }

  Future<void> _queue(Future<void> Function(NauvimEngine) operation) {
    final engine = _engine;
    if (_disposed || closing || engine == null) return Future.value();
    final attachment = _attachment;
    _input = _input.then((_) async {
      if (!_disposed && !closing && attachment == _attachment) {
        await _guard(() => operation(engine));
      }
    });
    return _input;
  }

  Future<void> sendKeys(String keys) {
    editor.clearSelection();
    return _queue((engine) => engine.input(keys: keys));
  }

  /// Chooses native text input for the current editor attachment.
  void setNativeTextInput(bool enabled) {
    if (_disposed || (enabled && !attached) || _nativeTextInput == enabled) {
      return;
    }
    _nativeTextInput = enabled;
    _changed();
  }

  /// Queues literal keyboard text from a composition on [attachment].
  Future<void> sendText(String text, {required int attachment}) {
    if (_disposed || !attached || attachment != _attachment || text.isEmpty) {
      return Future.value();
    }
    final keys = text.replaceAll('<', '<LT>');
    final queued = _queue((engine) => engine.input(keys: keys));
    editor.clearSelection();
    return queued;
  }

  Future<void> paste() => _queue((engine) => engine.paste());
  Future<void> focus(bool focused) =>
      _queue((engine) => engine.focus(focused: focused));
  Future<void> selectTab(int tabpage) =>
      _queue((engine) => engine.setCurrentTabpage(tabpage: tabpage));
  Future<void> selectBuffer(int buffer) =>
      _queue((engine) => engine.setCurrentBuffer(buffer: buffer));
  Future<void> selectCompletion(int index) =>
      _queue((engine) => engine.selectPopupmenuItem(index: index));

  Future<void> copySelection() async {
    if (!_disposed && !closing && editor.selectionStart != null) {
      await _guard(() => _platform.writeClipboard(editor.selectedText()));
    }
  }

  /// Waits for final diagnostics and native presentation cleanup before exit.
  Future<void> close() {
    if (_closeFuture case final future?) return future;
    if (_disposed) return Future.value();
    final done = Completer<void>();
    _closeFuture = done.future;
    unawaited(_close().then(done.complete, onError: done.completeError));
    return done.future;
  }

  Future<void> _close() async {
    _phase = SessionPhase.closing;
    _resize?.cancel();
    _resetAttachment();
    _changed();
    final engine = _engine;
    if (engine != null) {
      try {
        await engine.close();
      } catch (e) {
        reportError(e.toString());
        _platform.logError('Close Nauvim: $e');
      }
      await _updatesFinished.future;
    }
    await _subscription?.cancel();
    await _previews.drain();
    if (_errors.isNotEmpty) _platform.logError(_errors.join('\n'));
    if (!_disposed) await _guard(_platform.closeWindow);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finishUpdates();
    _resize?.cancel();
    _attachment++;
    _previews.reset();
    unawaited(_subscription?.cancel());
    _platform.setEventHandler(null);
    editor.dispose();
    super.dispose();
  }
}

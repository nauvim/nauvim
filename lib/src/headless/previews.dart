import 'dart:async';
import 'dart:ui' show Rect;

import 'editor_model.dart';
import 'platform.dart';
import 'protocol.dart';
import 'viewport.dart';

/// Tracks attachment-owned presentations while the skin supplies grid geometry.
final class Previews {
  Previews(this._platform, this._editor, this._reportError);

  final NauvimPlatform _platform;
  final EditorModel _editor;
  final void Function(String) _reportError;
  final _requests = <int, DisplayWindow>{};
  final _created = <int>{};
  final _rectangles = <int, Rect>{};
  final _operations = <int, Future<void>>{};
  EditorViewport? _viewport;
  bool _layoutReady = false;
  List<KeyBinding> keyBindings = const [];
  int _attachment = 0;

  void invalidateLayout() => _layoutReady = false;

  void layout(EditorViewport viewport, {required bool attached}) {
    _viewport = viewport;
    _layoutReady = attached;
    if (attached) _place();
  }

  void open(DisplayWindow window) {
    _requests[window.handle] = window;
    if (_layoutReady) _place();
  }

  void clear(int handle, {bool userRequested = false}) {
    // A plugin clear has no effect before its GUI presentation exists.
    final created = _created.remove(handle);
    if (!created && !userRequested) return;
    final window = _requests.remove(handle);
    _rectangles.remove(handle);
    _enqueue(handle, () async {
      try {
        if (created) await _platform.closePreview(handle);
      } finally {
        if (userRequested) await window?.webview?.closed();
      }
    });
  }

  void focus(int handle) {
    final window = _requests[handle];
    if (window != null) _enqueue(handle, () => _focus(window));
  }

  Future<bool> allowsNavigation(int handle, String url) async {
    final window = _requests[handle];
    final attachment = _attachment;
    final allowed = await window?.webview?.allowsNavigation(url: url);
    return allowed == true &&
        attachment == _attachment &&
        identical(_requests[handle], window);
  }

  Future<void> reportFailure(int handle, String message) async {
    if (_requests[handle] case final window?) {
      await _reportFailure(window, message);
    }
  }

  void reset() {
    _attachment++;
    _layoutReady = false;
    _requests.clear();
    _rectangles.clear();
    for (final handle in _created) {
      _enqueue(handle, () => _platform.closePreview(handle));
    }
    _created.clear();
    // Pending opens check the attachment again when their operation completes.
  }

  void _place() {
    final viewport = _viewport;
    if (viewport == null) return;
    for (final window in _requests.values) {
      final handle = window.handle;
      final attachment = _attachment;
      bool owned() =>
          attachment == _attachment && identical(_requests[handle], window);

      final grid = _editor.grids[window.grid]?.geometry;
      if (grid == null || grid.hidden) {
        if (_rectangles.remove(handle) != null) {
          _enqueue(handle, () async {
            if (owned() &&
                _created.contains(handle) &&
                !_rectangles.containsKey(handle)) {
              try {
                await _platform.hidePreview(handle);
              } catch (e) {
                await _reportFailure(window, 'Hide web preview: $e');
              }
            }
          });
        }
        continue;
      }
      final rectangle = viewport.previewRect(window, grid);
      if (_rectangles[handle] == rectangle) continue;
      _rectangles[handle] = rectangle;
      _enqueue(handle, () async {
        if (owned() && _rectangles[handle] == rectangle) {
          await _present(window, rectangle, owned);
        }
      });
    }
  }

  Future<void> _present(
    DisplayWindow window,
    Rect rectangle,
    bool Function() owned,
  ) async {
    final handle = window.handle;
    final opening = !_created.contains(handle);
    try {
      await _platform.openPreview(window, rectangle, keyBindings: keyBindings);
    } catch (e) {
      if (!owned()) return;
      if (_rectangles[handle] == rectangle) _rectangles.remove(handle);
      if (opening) _requests.remove(handle);
      try {
        await _reportFailure(window, 'Show web preview: $e');
      } finally {
        if (opening) await window.webview?.closed();
      }
      return;
    }

    if (!opening) return;
    if (!owned()) {
      // Close a late presentation before dispatching another use of the handle.
      await _platform.closePreview(handle);
      return;
    }

    _created.add(handle);
    if (await window.webview?.opened() == false) {
      if (owned()) clear(handle);
      return;
    }
    if (owned() && window.focus && _rectangles.containsKey(handle)) {
      await _focus(window);
    }
  }

  Future<void> _focus(DisplayWindow window) async {
    final handle = window.handle;
    final attachment = _attachment;
    if (!window.focusable ||
        !_created.contains(handle) ||
        !identical(_requests[handle], window)) {
      return;
    }
    if (await window.webview?.canFocus() != true ||
        attachment != _attachment ||
        !identical(_requests[handle], window)) {
      return;
    }
    try {
      await _platform.focusPreview(handle);
    } catch (e) {
      await _reportFailure(window, 'Focus web preview: $e');
    }
  }

  Future<void> _reportFailure(DisplayWindow window, String message) async {
    if (window.webview case final webview?) {
      await webview.reportError(message: message);
    } else {
      _reportError(message);
    }
  }

  void _enqueue(int handle, Future<void> Function() operation) {
    final previous = _operations[handle] ?? Future<void>.value();
    final next = previous.then((_) async {
      try {
        await operation();
      } catch (e) {
        _reportError(e.toString());
      }
    });
    _operations[handle] = next;
    unawaited(
      next.then((_) {
        if (identical(_operations[handle], next)) _operations.remove(handle);
      }),
    );
  }

  Future<void> drain() async {
    while (_operations.isNotEmpty) {
      await Future.wait(_operations.values.toList());
    }
  }
}

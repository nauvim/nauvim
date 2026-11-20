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

  void clear(int handle) {
    // A plugin clear has no effect before its GUI presentation exists.
    if (!_created.remove(handle)) return;
    _requests.remove(handle);
    _rectangles.remove(handle);
    _enqueue(handle, () => _platform.closePreview(handle));
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
      final grid = _editor.grids[window.grid]?.geometry;
      if (grid == null || grid.hidden) {
        _rectangles.remove(window.handle);
        if (_created.remove(window.handle)) {
          _enqueue(window.handle, () => _platform.closePreview(window.handle));
        }
        continue;
      }
      final rectangle = viewport.previewRect(window, grid);
      if (_rectangles[window.handle] == rectangle) continue;
      _rectangles[window.handle] = rectangle;
      final attachment = _attachment;
      _enqueue(window.handle, () async {
        bool owned() =>
            attachment == _attachment &&
            identical(_requests[window.handle], window) &&
            _rectangles.containsKey(window.handle);
        if (!owned() || _rectangles[window.handle] != rectangle) return;
        await _platform.openPreview(window, rectangle);
        if (owned()) {
          _created.add(window.handle);
        } else {
          // Serialize this cleanup before a later use of the same handle.
          await _platform.closePreview(window.handle);
        }
      });
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

import 'dart:ui' show Rect;

import 'protocol.dart';
import 'viewport.dart';
import 'window_geometry.dart';

sealed class NauvimPlatformEvent {
  const NauvimPlatformEvent();
}

final class WindowCloseRequested extends NauvimPlatformEvent {
  const WindowCloseRequested();
}

final class WindowSizeChanged extends NauvimPlatformEvent {
  const WindowSizeChanged(this.width, this.height);
  final int width, height;
}

final class PlatformFailure extends NauvimPlatformEvent {
  const PlatformFailure(this.message);
  final String message;
}

final class PreviewCloseRequested extends NauvimPlatformEvent {
  const PreviewCloseRequested(this.handle);
  final int handle;
}

final class PreviewNavigationRequested extends NauvimPlatformEvent {
  PreviewNavigationRequested(this.handle, this.url);
  final int handle;
  final String url;
  bool allowed = false;
}

final class PreviewFailure extends NauvimPlatformEvent {
  const PreviewFailure(this.handle, this.message);
  final int handle;
  final String message;
}

/// Native capabilities used by application behavior, independently of its skin.
abstract interface class NauvimPlatform {
  /// Replaces the application's event handler; null removes it on disposal.
  void setEventHandler(Future<void> Function(NauvimPlatformEvent)? handler);
  Future<EditorFont> resolveFonts(List<DisplayFont> fonts);

  /// Applies resolved startup options in logical pixels, preserving omitted axes.
  Future<void> configureInitialWindow(WindowOptions options);
  Future<void> configureWindowGrid(WindowGrid grid);
  Future<void> setTitle(String title);
  Future<void> alert();
  Future<void> writeClipboard(String text);

  /// Creates or positions a presentation in logical native-window coordinates.
  ///
  /// Completes after creation and placement, without awaiting URL navigation.
  /// A native navigation waits for [PreviewNavigationRequested] to be handled.
  Future<void> openPreview(
    DisplayWindow window,
    Rect rectangle, {
    List<KeyBinding> keyBindings = const [],
  });
  Future<void> hidePreview(int handle);
  Future<void> focusPreview(int handle);
  Future<void> closePreview(int handle);

  /// Requests native window closure after the controller has finalized work.
  Future<void> closeWindow();
  void logError(String message);
}

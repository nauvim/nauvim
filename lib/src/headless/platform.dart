import 'dart:ui' show Rect;

import 'protocol.dart';
import 'viewport.dart';

sealed class NauvimPlatformEvent {
  const NauvimPlatformEvent();
}

final class WindowCloseRequested extends NauvimPlatformEvent {
  const WindowCloseRequested();
}

final class PlatformFailure extends NauvimPlatformEvent {
  const PlatformFailure(this.message);
  final String message;
}

/// Native capabilities used by application behavior, independently of its skin.
abstract interface class NauvimPlatform {
  /// Replaces the application's event handler; null removes it on disposal.
  void setEventHandler(Future<void> Function(NauvimPlatformEvent)? handler);
  Future<EditorFont> resolveFonts(List<DisplayFont> fonts);

  /// Sets the initial client-area size in logical pixels, preserving omitted axes.
  Future<void> configureInitialWindow(DisplayWindowOptions options);
  Future<void> configureWindowGrid(WindowGrid grid);
  Future<void> setTitle(String title);
  Future<void> alert();
  Future<void> writeClipboard(String text);

  /// Creates or positions a presentation in logical native-window coordinates.
  ///
  /// Completes after creation and placement dispatch, without awaiting URL
  /// navigation. Navigation failures arrive through [PlatformFailure].
  Future<void> openPreview(DisplayWindow window, Rect rectangle);
  Future<void> closePreview(int handle);

  /// Requests native window closure after the controller has finalized work.
  Future<void> closeWindow();
  void logError(String message);
}

import 'dart:io';

import 'package:flutter/services.dart';

import '../headless/platform.dart';
import '../headless/protocol.dart';
import '../headless/viewport.dart';
import '../headless/window_geometry.dart';
import '../bridge/api/fonts.dart' as native_fonts;

/// Desktop capabilities implemented by the Linux and macOS runners.
final class DesktopNauvimPlatform implements NauvimPlatform {
  DesktopNauvimPlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('io.nauvim/window');

  final MethodChannel _channel;
  Future<void> Function(NauvimPlatformEvent)? _eventHandler;
  static int _nextFontFamily = 0;

  @override
  void setEventHandler(Future<void> Function(NauvimPlatformEvent)? handler) {
    _eventHandler = handler;
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              switch (call.method) {
                case 'close_requested':
                  await handler(const WindowCloseRequested());
                case 'window_size_changed':
                  if (call.arguments case [final num width, final num height]
                      when _isWindowDimension(width) &&
                          _isWindowDimension(height)) {
                    await handler(
                      WindowSizeChanged(width.round(), height.round()),
                    );
                  }
                case 'window_error':
                  await handler(PlatformFailure(call.arguments.toString()));
                case 'close_webview_requested':
                  await handler(PreviewCloseRequested(call.arguments as int));
                case 'webview_allows_navigation':
                  final args = call.arguments as Map;
                  final event = PreviewNavigationRequested(
                    args['handle'] as int,
                    args['url'] as String,
                  );
                  await handler(event);
                  return event.allowed;
                case 'webview_error':
                  final args = call.arguments as Map;
                  await handler(
                    PreviewFailure(
                      args['handle'] as int,
                      args['message'] as String,
                    ),
                  );
              }
            },
    );
  }

  static bool _isWindowDimension(num value) =>
      value >= 1 && value <= 0xffffffff;

  @override
  Future<EditorFont> resolveFonts(List<DisplayFont> fonts) async {
    Future<native_fonts.FontResolution> resolve(
      List<DisplayFont> requested,
    ) async {
      final candidates = requested.every((font) => font.path != null)
          ? const <dynamic>[]
          : await _channel.invokeListMethod<dynamic>(
                  'font_candidates',
                  requested
                      .map((font) => font.path == null ? font.family : '')
                      .toList(),
                ) ??
                const <dynamic>[];
      final result = await native_fonts.resolveFonts(
        requests: [
          for (final font in requested)
            native_fonts.FontRequest(
              family: font.family,
              subfamily: font.subfamily,
              path: font.path,
            ),
        ],
        candidates: [
          for (final entry in candidates)
            native_fonts.FontCandidate(
              request: entry['request'] as int,
              path: entry['path'] as String,
              index: entry['index'] as int,
              postscriptName: entry['postscript'] as String?,
            ),
        ],
      );
      for (final diagnostic in result.diagnostics) {
        await _eventHandler?.call(PlatformFailure(diagnostic));
      }
      return result;
    }

    var requested = fonts;
    var result = await resolve(requested);
    if (result.fonts.isEmpty) {
      requested = const [DisplayFont(family: 'monospace', size: 15)];
      result = await resolve(requested);
    }
    if (result.fonts.isEmpty) {
      throw StateError('No usable system monospace font');
    }
    final faces = <EditorFontFace>[];
    for (final resolved in result.fonts) {
      final family = 'com.naughie.nauvim.flutter.font.${_nextFontFamily++}';
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(resolved.data)));
      await loader.load();
      final info = resolved.info;
      faces.add(
        EditorFontFace(
          family: family,
          size: requested[resolved.request].size,
          ascent: info.ascent,
          descent: info.descent,
          lineGap: info.lineGap,
          advance: info.advance,
          coverage: List.unmodifiable(
            info.coverage.map((range) => (range.first, range.last)),
          ),
          variations: List.unmodifiable(
            resolved.variations.map((axis) => (axis.axis, axis.value)),
          ),
        ),
      );
    }
    return EditorFont(faces: faces);
  }

  @override
  Future<void> configureInitialWindow(WindowOptions options) =>
      _channel.invokeMethod('configure_window', {
        if (options.width != null) 'width': options.width,
        if (options.height != null) 'height': options.height,
        'decorations': (options.decorations ?? DisplayDecorations.full).name,
        'opacity': options.opacity ?? 1.0,
        'startup_mode':
            (options.startupMode ?? DisplayStartupMode.windowed).name,
      });

  @override
  Future<void> configureWindowGrid(WindowGrid grid) =>
      _channel.invokeMethod('configure_grid', {
        'cell_width': grid.cellWidth,
        'cell_height': grid.cellHeight,
        'base_width': grid.baseWidth,
        'base_height': grid.baseHeight,
        'min_rows': grid.minRows,
      });

  @override
  Future<void> setTitle(String title) =>
      _channel.invokeMethod('title', {'title': title});

  @override
  Future<void> alert() => SystemSound.play(SystemSoundType.alert);

  @override
  Future<void> writeClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Future<void> openPreview(
    DisplayWindow window,
    Rect rectangle, {
    List<KeyBinding> keyBindings = const [],
  }) => _channel.invokeMethod('open_webview', {
    'handle': window.handle,
    'url': window.url,
    'focusable': window.focusable,
    'x': rectangle.left,
    'y': rectangle.top,
    'width': rectangle.width,
    'height': rectangle.height,
    'key_bindings': [
      for (final binding in keyBindings)
        if (binding.action case final action?)
          {
            'key': binding.key,
            'modifiers': binding.modifiers,
            'action': action.name,
          },
    ],
  });

  @override
  Future<void> hidePreview(int handle) =>
      _channel.invokeMethod('hide_webview', {'handle': handle});

  @override
  Future<void> focusPreview(int handle) =>
      _channel.invokeMethod('focus_webview', {'handle': handle});

  @override
  Future<void> closePreview(int handle) =>
      _channel.invokeMethod('close_webview', {'handle': handle});

  @override
  Future<void> closeWindow() => _channel.invokeMethod('close');

  @override
  void logError(String message) => stderr.writeln(message);
}

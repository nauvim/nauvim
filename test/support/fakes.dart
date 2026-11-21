import 'dart:async';
import 'dart:ui';

import 'package:nauvim_flutter/nauvim.dart';

EditorFont fixtureFonts(Iterable<DisplayFont> fonts) => EditorFont(
  faces: fonts.map(
    (f) => EditorFontFace(
      family: f.family,
      size: f.size,
      ascent: .8,
      descent: .2,
      lineGap: 0,
      advance: .6,
      coverage: const [(0, 0x10ffff)],
    ),
  ),
);

class FakeEngine implements NauvimEngine {
  final events = StreamController<UiUpdate>(sync: true);
  final starts = <(int, int)>[];
  final defaults = <(int, int)>[];
  final connections = <(String, int, int)>[];
  final inputs = <String>[];
  final resizes = <(int, int)>[];
  int detaches = 0, pastes = 0, closes = 0;
  void emit(UiUpdate update) => events.add(update);

  @override
  Stream<UiUpdate> updates() => events.stream;
  @override
  Future<void> start({required int width, required int height}) async =>
      starts.add((width, height));
  @override
  Future<void> connect({
    required String host,
    required int width,
    required int height,
  }) async => connections.add((host, width, height));
  @override
  Future<void> connectDefault({
    required int width,
    required int height,
  }) async => defaults.add((width, height));
  @override
  Future<void> detach() async => detaches++;
  @override
  Future<void> input({required String keys}) async => inputs.add(keys);
  @override
  Future<void> paste() async => pastes++;
  @override
  Future<void> resize({required int width, required int height}) async =>
      resizes.add((width, height));
  @override
  Future<void> focus({required bool focused}) async {}
  @override
  Future<void> selectPopupmenuItem({required int index}) async {}
  @override
  Future<void> setCurrentTabpage({required int tabpage}) async {}
  @override
  Future<void> setCurrentBuffer({required int buffer}) async {}
  @override
  Future<void> close() async {
    closes++;
    emit(const UiUpdate(kind: 'shutdown', hosts: [], fonts: []));
  }
}

class FakePlatform implements NauvimPlatform {
  Future<void> Function(NauvimPlatformEvent)? eventHandler;
  final titles = <String>[];
  final clipboard = <String>[];
  final previews = <(DisplayWindow, Rect)>[];
  final closedPreviews = <int>[];
  final diagnostics = <String>[];
  final initialWindows = <WindowOptions>[];
  final windowGrids = <WindowGrid>[];
  int alerts = 0, closes = 0;

  @override
  void setEventHandler(Future<void> Function(NauvimPlatformEvent)? handler) =>
      eventHandler = handler;
  @override
  Future<EditorFont> resolveFonts(List<DisplayFont> fonts) async =>
      fixtureFonts(fonts);
  @override
  Future<void> configureInitialWindow(WindowOptions options) async =>
      initialWindows.add(options);
  @override
  Future<void> configureWindowGrid(WindowGrid grid) async =>
      windowGrids.add(grid);
  @override
  Future<void> setTitle(String title) async => titles.add(title);
  @override
  Future<void> alert() async => alerts++;
  @override
  Future<void> writeClipboard(String text) async => clipboard.add(text);
  @override
  Future<void> openPreview(
    DisplayWindow window,
    Rect rectangle, {
    List<KeyBinding> keyBindings = const [],
  }) async => previews.add((window, rectangle));
  @override
  Future<void> closePreview(int handle) async => closedPreviews.add(handle);
  @override
  Future<void> closeWindow() async => closes++;
  @override
  void logError(String message) => diagnostics.add(message);
}

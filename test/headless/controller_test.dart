import 'dart:async';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:nauvim_flutter/src/headless/controller.dart';
import 'package:nauvim_flutter/src/headless/editor_model.dart';
import 'package:nauvim_flutter/src/headless/engine.dart';
import 'package:nauvim_flutter/src/headless/platform.dart';
import 'package:nauvim_flutter/src/headless/protocol.dart';
import 'package:nauvim_flutter/src/headless/viewport.dart';

import '../support/fakes.dart' show fixtureFonts;

final class Update extends UiUpdate {
  const Update({
    required super.kind,
    super.frame,
    super.window,
    super.windowOptions,
    super.message,
    super.fonts = const [],
    super.hosts = const [],
  });
}

final class Engine implements NauvimEngine {
  final events = StreamController<UiUpdate>(sync: true);
  final calls = <(String, Object?)>[];
  Completer<void>? inputGate;

  @override
  Stream<UiUpdate> updates() => events.stream;
  @override
  Future<void> start({required int width, required int height}) async =>
      calls.add(('start', (width, height)));
  @override
  Future<void> connect({
    required String host,
    required int width,
    required int height,
  }) async => calls.add(('connect', (host, width, height)));
  @override
  Future<void> connectDefault({
    required int width,
    required int height,
  }) async => calls.add(('default', (width, height)));
  @override
  Future<void> detach() async => calls.add(('detach', null));
  @override
  Future<void> close() async => calls.add(('close', null));
  @override
  Future<void> input({required String keys}) async {
    calls.add(('keys', keys));
    await inputGate?.future;
  }

  @override
  Future<void> paste() async => calls.add(('paste', null));
  @override
  Future<void> resize({required int width, required int height}) async =>
      calls.add(('resize', (width, height)));
  @override
  Future<void> focus({required bool focused}) async =>
      calls.add(('focus', focused));
  @override
  Future<void> selectPopupmenuItem({required int index}) async =>
      calls.add(('popup', index));
  @override
  Future<void> setCurrentTabpage({required int tabpage}) async =>
      calls.add(('tab', tabpage));
  @override
  Future<void> setCurrentBuffer({required int buffer}) async =>
      calls.add(('buffer', buffer));
}

final class Platform implements NauvimPlatform {
  final calls = <(String, Object?)>[];
  final logs = <String>[];
  Future<void> Function(NauvimPlatformEvent)? handler;
  Completer<List<String>>? fontGate;
  Completer<void>? previewGate;
  Completer<void>? windowGate;

  @override
  void setEventHandler(Future<void> Function(NauvimPlatformEvent)? handler) =>
      this.handler = handler;
  @override
  Future<EditorFont> resolveFonts(List<DisplayFont> fonts) async {
    final available =
        await (fontGate?.future ??
            Future.value(fonts.map((f) => f.family).toList()));
    return fixtureFonts(fonts.where((f) => available.contains(f.family)));
  }

  @override
  Future<void> configureInitialWindow(DisplayWindowOptions options) async {
    calls.add(('initial_window', options));
    await windowGate?.future;
  }

  @override
  Future<void> configureWindowGrid(WindowGrid grid) async {}
  @override
  Future<void> setTitle(String title) async => calls.add(('title', title));
  @override
  Future<void> alert() async => calls.add(('alert', null));
  @override
  Future<void> writeClipboard(String text) async => calls.add(('copy', text));
  @override
  Future<void> openPreview(DisplayWindow window, Rect rectangle) async {
    calls.add(('open', (window.handle, rectangle)));
    await previewGate?.future;
  }

  @override
  Future<void> closePreview(int handle) async => calls.add(('clear', handle));
  @override
  Future<void> closeWindow() async => calls.add(('exit', null));
  @override
  void logError(String message) => logs.add(message);
}

const grid = DisplayGrid(
  id: 1,
  width: 80,
  height: 24,
  row: 2,
  col: 3,
  zindex: 0,
  order: 0,
  hidden: false,
);
const preview = DisplayWindow(
  handle: 47,
  url: 'https://localhost/preview#part',
  grid: 1,
  top: 2,
  left: 1,
  height: 3,
  width: 5,
);

DisplayFrame frame({
  List<DisplayEvent> events = const [],
  List<DisplayRow> rows = const [],
}) => DisplayFrame(
  full: false,
  grids: const [grid],
  removedGrids: const [],
  rows: rows,
  highlights: const [],
  foreground: 0xffffff,
  background: 0,
  title: '',
  mode: 'normal',
  busy: false,
  widgets: const [],
  events: events,
);

EditorViewport viewport(
  NauvimController controller, {
  double width = 800,
  Offset origin = const Offset(4, 40),
}) => EditorViewport(
  font: controller.font,
  size: Size(width, 480),
  cellWidth: 10,
  cellHeight: 20,
  origin: origin,
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Engine engine;
  late Platform platform;
  late NauvimController controller;
  setUp(() {
    engine = Engine();
    platform = Platform();
    controller = NauvimController(engine: engine, platform: platform);
  });
  tearDown(() async {
    controller.dispose();
    await engine.events.close();
  });

  test(
    'applies initial window options once before font discovery and startup',
    () async {
      const margins = DisplayMargins(top: 3, bottom: 5, left: 7, right: 11);
      const options = DisplayWindowOptions(
        width: 960,
        height: 640,
        margin: margins,
        decorations: DisplayDecorations.none,
        opacity: 0.8,
        startupMode: DisplayStartupMode.fullscreen,
      );
      platform.windowGate = Completer();
      engine.events.add(const Update(kind: 'ready', windowOptions: options));
      engine.events.add(const Update(kind: 'ready', windowOptions: options));
      await settle();
      expect(platform.calls, [('initial_window', options)]);
      expect(controller.windowMargins, same(margins));
      expect(controller.ready, isFalse);
      controller.updateViewport(viewport(controller));
      expect(engine.calls, isEmpty);

      platform.windowGate!.complete();
      await settle();
      expect(controller.ready, isTrue);
      controller.updateViewport(viewport(controller));
      await settle();
      expect(engine.calls, [('start', (80, 24))]);
      engine.events.add(
        const Update(
          kind: 'ready',
          windowOptions: DisplayWindowOptions(
            width: 1000,
            height: 700,
            margin: DisplayMargins(top: 0, bottom: 0, left: 0, right: 0),
          ),
        ),
      );
      await settle();
      expect(platform.calls, [('initial_window', options)]);
      expect(controller.windowMargins, same(margins));
    },
  );

  test('starts once after font discovery and a matching viewport without a widget tree', () async {
    platform.fontGate = Completer();
    controller.updateViewport(viewport(controller));
    engine.events.add(
      const Update(
        kind: 'ready',
        fonts: [DisplayFont(family: 'mono', size: 14)],
      ),
    );
    expect(engine.calls, isEmpty);
    final oldFont = controller.font;
    platform.fontGate!.complete(['mono']);
    await settle();
    expect(controller.ready, isTrue);
    expect(controller.font.families, ['mono']);
    expect(controller.font.size, 14);
    expect(engine.calls, isEmpty);
    controller.updateViewport(
      EditorViewport(
        font: oldFont,
        size: const Size(800, 480),
        cellWidth: 10,
        cellHeight: 20,
      ),
    );
    expect(engine.calls, isEmpty);
    controller.updateViewport(viewport(controller));
    await settle();
    expect(engine.calls, [('start', (80, 24))]);
    engine.events.add(const Update(kind: 'welcome'));
    controller.updateViewport(viewport(controller));
    await settle();
    expect(engine.calls, [('start', (80, 24))]);
  });

  test(
    'rejects invalid viewport metrics before converting or sending dimensions',
    () async {
      engine.events.add(const Update(kind: 'ready'));
      await settle();
      for (final metrics in [
        (const Size(800, 480), 0.0, 20.0),
        (const Size(800, 480), double.nan, 20.0),
        (const Size(800, 480), 1e-320, 20.0),
        (const Size(-1, 480), 10.0, 20.0),
        (const Size(1e20, 480), 10.0, 20.0),
      ]) {
        controller.updateViewport(
          EditorViewport(
            font: controller.font,
            size: metrics.$1,
            cellWidth: metrics.$2,
            cellHeight: metrics.$3,
          ),
        );
      }
      expect(engine.calls, isEmpty);
      expect(controller.errors, [
        'Measure editor viewport: invalid dimensions',
      ]);
      controller.updateViewport(viewport(controller));
      await settle();
      expect(engine.calls, [('start', (80, 24))]);
    },
  );

  test(
    'keeps destination selection and cancellation independent of appearance',
    () async {
      controller.updateViewport(viewport(controller));
      await controller.connectDefault();
      expect(controller.phase, SessionPhase.connecting);
      expect(engine.calls, [('default', (80, 24))]);
      engine.events.add(const Update(kind: 'welcome'));
      await controller.connect('local');
      expect(engine.calls.last, ('connect', ('local', 80, 24)));
      expect(controller.destination, 'local');
      await controller.detach();
      expect(engine.calls.last, ('detach', null));
      // A manual choice suppresses a later automatic startup request.
      engine.events.add(const Update(kind: 'ready'));
      await settle();
      expect(engine.calls.where((call) => call.$1 == 'start'), isEmpty);
    },
  );

  test('keeps frame notifications separate from application chrome', () async {
    var chrome = 0, paints = 0;
    controller.addListener(() => chrome++);
    controller.editor.addListener(() => paints++);
    engine.events.add(Update(kind: 'frame', frame: frame()));
    expect(chrome, 1);
    expect(paints, 1);
    chrome = 0;
    engine.events.add(
      Update(
        kind: 'frame',
        frame: frame(
          events: const [
            DisplayEvent(kind: 'title', text: 'first'),
            DisplayEvent(kind: 'bell', text: ''),
            DisplayEvent(kind: 'title', text: 'second'),
          ],
        ),
      ),
    );
    await settle();
    expect(chrome, 0);
    expect(paints, 2);
    expect(platform.calls, [
      ('title', 'first'),
      ('alert', null),
      ('title', 'second'),
    ]);
  });

  test(
    'orders input and discards actions queued for an earlier attachment',
    () async {
      engine.events.add(Update(kind: 'frame', frame: frame()));
      engine.inputGate = Completer();
      final first = controller.sendKeys('first');
      final stale = controller.sendKeys('stale');
      await settle();
      expect(engine.calls, [('keys', 'first')]);
      engine.events.add(const Update(kind: 'welcome'));
      engine.events.add(Update(kind: 'frame', frame: frame()));
      engine.inputGate!.complete();
      await first;
      await stale;
      await controller.sendKeys('current');
      await controller.selectTab(202);
      await controller.selectBuffer(303);
      await controller.selectCompletion(1);
      await controller.paste();
      expect(engine.calls, [
        ('keys', 'first'),
        ('keys', 'current'),
        ('tab', 202),
        ('buffer', 303),
        ('popup', 1),
        ('paste', null),
      ]);
    },
  );

  test('copies only the independently selected grid text and clears selection on keys', () async {
    engine.events.add(
      Update(
        kind: 'frame',
        frame: frame(
          rows: const [
            DisplayRow(
              grid: 1,
              row: 0,
              cells: [
                DisplayCell(text: '界', highlight: 0),
                DisplayCell(text: '', highlight: 0),
                DisplayCell(text: 'a', highlight: 0),
              ],
            ),
          ],
        ),
      ),
    );
    controller.editor.beginSelection(const CellPoint(1, 0, 0));
    controller.editor.extendSelection(const CellPoint(1, 0, 2));
    await controller.copySelection();
    expect(platform.calls, [('copy', '界a')]);
    await controller.sendKeys('x');
    expect(controller.editor.selectionStart, isNull);
  });

  test(
    'debounces dimensions while native placement uses the latest layout origin',
    () async {
      engine.events.add(const Update(kind: 'ready'));
      await settle();
      controller.updateViewport(viewport(controller));
      engine.events.add(Update(kind: 'frame', frame: frame()));
      engine.events.add(const Update(kind: 'open_webview', window: preview));
      expect(platform.calls, isEmpty);
      controller.updateViewport(viewport(controller));
      await settle();
      expect(platform.calls.single, (
        'open',
        (47, const Rect.fromLTWH(44, 120, 50, 60)),
      ));
      controller.updateViewport(viewport(controller));
      await settle();
      expect(platform.calls, hasLength(1));
      controller.updateViewport(
        viewport(controller, width: 700, origin: const Offset(14, 50)),
      );
      controller.updateViewport(
        viewport(controller, width: 600, origin: const Offset(14, 50)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(engine.calls.where((call) => call.$1 == 'resize').toList(), [
        ('resize', (60, 24)),
      ]);
      expect(platform.calls.last, (
        'open',
        (47, const Rect.fromLTWH(54, 130, 50, 60)),
      ));
    },
  );

  test('moves an opening preview without closing or reloading it', () async {
    final first = Completer<void>();
    final second = Completer<void>();
    platform.previewGate = first;
    engine.events.add(Update(kind: 'frame', frame: frame()));
    controller.updateViewport(viewport(controller));
    engine.events.add(const Update(kind: 'open_webview', window: preview));
    await settle();
    expect(platform.calls, [
      ('open', (47, const Rect.fromLTWH(44, 120, 50, 60))),
    ]);
    controller.updateViewport(
      viewport(controller, origin: const Offset(14, 50)),
    );
    platform.previewGate = second;
    first.complete();
    await settle();
    expect(platform.calls, [
      ('open', (47, const Rect.fromLTWH(44, 120, 50, 60))),
      ('open', (47, const Rect.fromLTWH(54, 130, 50, 60))),
    ]);
    second.complete();
    await settle();
    engine.events.add(const Update(kind: 'welcome'));
    await settle();
    expect(platform.calls, [
      ('open', (47, const Rect.fromLTWH(44, 120, 50, 60))),
      ('open', (47, const Rect.fromLTWH(54, 130, 50, 60))),
      ('clear', 47),
    ]);
  });

  test('keeps a pending clear harmless and cleans late presentation completions on detach', () async {
    engine.events.add(const Update(kind: 'open_webview', window: preview));
    engine.events.add(const Update(kind: 'close_webview', window: preview));
    engine.events.add(Update(kind: 'frame', frame: frame()));
    controller.updateViewport(viewport(controller));
    platform.previewGate = Completer();
    await settle();
    expect(platform.calls.single.$1, 'open');
    engine.events.add(const Update(kind: 'close_webview', window: preview));
    expect(platform.calls, hasLength(1));
    engine.events.add(const Update(kind: 'welcome'));
    platform.previewGate!.complete();
    await settle();
    expect(platform.calls, [
      ('open', (47, const Rect.fromLTWH(44, 120, 50, 60))),
      ('clear', 47),
    ]);
    engine.events.add(Update(kind: 'frame', frame: frame()));
    controller.updateViewport(viewport(controller));
    await settle();
    expect(platform.calls, hasLength(2));
  });

  test(
    'awaits final diagnostics and pending native cleanup before closing once',
    () async {
      engine.events.add(Update(kind: 'frame', frame: frame()));
      controller.updateViewport(viewport(controller));
      platform.previewGate = Completer();
      engine.events.add(const Update(kind: 'open_webview', window: preview));
      await settle();
      final close = controller.close();
      expect(identical(close, controller.close()), isTrue);
      await settle();
      expect(engine.calls.last, ('close', null));
      expect(platform.calls.where((call) => call.$1 == 'exit'), isEmpty);
      engine.events.add(
        const Update(kind: 'error', message: 'Final cleanup failed'),
      );
      expect(controller.errors, ['Final cleanup failed']);
      engine.events.add(const Update(kind: 'shutdown'));
      await settle();
      expect(platform.calls.where((call) => call.$1 == 'exit'), isEmpty);
      platform.previewGate!.complete();
      await close;
      expect(platform.calls.map((call) => call.$1), ['open', 'clear', 'exit']);
      expect(platform.logs, ['Final cleanup failed']);
      expect(controller.phase, SessionPhase.closing);
    },
  );

  for (final terminal in ['done', 'error']) {
    test(
      'finishes shutdown after the engine stream reports $terminal',
      () async {
        if (terminal == 'done') {
          await engine.events.close();
        } else {
          engine.events.addError(StateError('Engine failed'));
        }
        await controller.close();
        expect(platform.calls.last, ('exit', null));
        if (terminal == 'error') {
          expect(controller.errors.single, contains('Engine failed'));
        }
      },
    );
  }

  test('closes an engine-free startup error and exposes immutable diagnostic snapshots', () async {
    controller.dispose();
    controller = NauvimController(
      platform: platform,
      startupError: 'Engine unavailable',
    );
    final errors = controller.errors;
    expect(errors, ['Engine unavailable']);
    expect(() => errors.add('bad'), throwsUnsupportedError);
    controller.reportError('Another error');
    controller.reportError('Another error');
    expect(controller.errors, ['Another error', 'Engine unavailable']);
    expect(errors, ['Engine unavailable']);
    await platform.handler!(const WindowCloseRequested());
    expect(platform.calls.last, ('exit', null));
    expect(platform.logs, ['Another error\nEngine unavailable']);
  });
}

import 'package:nauvim_flutter/nauvim.dart';
import 'package:nauvim_flutter/nauvim_desktop.dart';

import 'support/fakes.dart' show fixtureFonts;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nauvim_flutter/main.dart';
import 'package:nauvim_flutter/nauvim_widgets.dart';
import 'package:nauvim_flutter/src/bridge/api/application.dart';

class FakeApplication implements Application {
  final controller = StreamController<UiUpdate>(sync: true);
  final starts = <(int, int)>[];
  final defaults = <(int, int)>[];
  final connections = <(String, int, int)>[];
  final inputs = <String>[];
  final windowSizes = <(int, int)>[];
  final tabpages = <int>[];
  final buffers = <int>[];
  final completions = <int>[];
  int pastes = 0, closes = 0, detaches = 0;
  @override
  bool isDisposed = false;

  @override
  void dispose() => isDisposed = true;
  @override
  Stream<UiUpdate> updates() => controller.stream;
  @override
  Future<void> start({required int width, required int height}) async =>
      starts.add((width, height));
  @override
  Future<void> connectDefault({
    required int width,
    required int height,
  }) async => defaults.add((width, height));
  @override
  Future<void> connect({
    required String host,
    required int width,
    required int height,
  }) async => connections.add((host, width, height));
  @override
  Future<void> detach() async => detaches++;
  @override
  Future<void> focus({required bool focused}) async {}
  @override
  Future<void> input({required String keys}) async => inputs.add(keys);
  @override
  Future<void> paste() async => pastes++;
  @override
  Future<void> resize({required int width, required int height}) async {}
  @override
  void recordWindowSize({required int width, required int height}) =>
      windowSizes.add((width, height));
  @override
  Future<void> selectPopupmenuItem({required int index}) async =>
      completions.add(index);
  @override
  Future<void> setCurrentBuffer({required int buffer}) async =>
      buffers.add(buffer);
  @override
  Future<void> setCurrentTabpage({required int tabpage}) async =>
      tabpages.add(tabpage);
  @override
  Future<void> close() async {
    closes++;
  }
}

class TestPlatform implements NauvimPlatform {
  final native = DesktopNauvimPlatform();
  Completer<List<String>>? fontGate;
  @override
  Future<EditorFont> resolveFonts(List<DisplayFont> fonts) async {
    final available =
        await (fontGate?.future ??
            Future.value(fonts.map((f) => f.family).toList()));
    return fixtureFonts(fonts.where((f) => available.contains(f.family)));
  }

  @override
  void setEventHandler(Future<void> Function(NauvimPlatformEvent)? handler) =>
      native.setEventHandler(handler);
  @override
  Future<void> configureInitialWindow(WindowOptions options) =>
      native.configureInitialWindow(options);
  @override
  Future<void> configureWindowGrid(WindowGrid grid) =>
      native.configureWindowGrid(grid);
  @override
  Future<void> setTitle(String title) => native.setTitle(title);
  @override
  Future<void> alert() => native.alert();
  @override
  Future<void> writeClipboard(String text) => native.writeClipboard(text);
  @override
  Future<void> openPreview(
    DisplayWindow window,
    Rect rectangle, {
    List<KeyBinding> keyBindings = const [],
  }) => native.openPreview(window, rectangle, keyBindings: keyBindings);
  @override
  Future<void> hidePreview(int handle) => native.hidePreview(handle);
  @override
  Future<void> focusPreview(int handle) => native.focusPreview(handle);
  @override
  Future<void> navigatePreview(
    int handle, {
    required String url,
    required bool replaceHistory,
    required bool focus,
  }) => native.navigatePreview(
    handle,
    url: url,
    replaceHistory: replaceHistory,
    focus: focus,
  );
  @override
  Future<void> closePreview(int handle) => native.closePreview(handle);
  @override
  Future<void> closeWindow() => native.closeWindow();
  @override
  void logError(String message) => native.logError(message);
}

UiUpdate update(
  String kind, {
  DisplayFrame? frame,
  DisplayWindow? window,
  String? message,
  List<String> hosts = const [],
  List<DisplayFont> fonts = const [],
}) => UiUpdate(
  kind: kind,
  frame: frame,
  window: window,
  message: message,
  hosts: hosts,
  fonts: fonts,
);

DisplayGrid grid(int id) => DisplayGrid(
  id: id,
  width: 40,
  height: 12,
  row: id == 1 ? 0 : 2,
  col: id == 1 ? 0 : 3,
  zindex: id,
  order: id,
  hidden: false,
);

DisplayFrame frame({
  List<DisplayGrid>? grids,
  List<DisplayWidget> widgets = const [],
  List<DisplayEvent> events = const [],
}) => DisplayFrame(
  full: true,
  grids: grids ?? [grid(1)],
  removedGrids: const [],
  rows: const [],
  highlights: const [],
  foreground: 0xffffff,
  background: 0x15181e,
  title: '',
  mode: 'normal',
  busy: false,
  widgets: widgets,
  events: events,
);

DisplayWidget widget(
  String kind, {
  List<String> items = const [],
  List<int> handles = const [],
  List<DisplayChunk> chunks = const [],
}) => DisplayWidget(
  kind: kind,
  grid: 1,
  row: 1,
  col: 1,
  selected: 0,
  chunks: chunks,
  items: items,
  handles: handles,
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.nauvim/window');
  late List<MethodCall> nativeCalls;
  Future<Object?> Function(MethodCall)? nativeResponse;
  late TestPlatform platform;

  setUp(() {
    nativeCalls = [];
    platform = TestPlatform();
    nativeResponse = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      nativeCalls.add(call);
      return nativeResponse?.call(call);
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<FakeApplication> mount(WidgetTester tester) async {
    final app = FakeApplication();
    await tester.pumpWidget(NauvimApp(application: app, platform: platform));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await app.controller.close();
    });
    return app;
  }

  Future<void> emit(
    WidgetTester tester,
    FakeApplication app,
    UiUpdate value,
  ) async {
    app.controller.add(value);
    await tester.pump();
    await tester.pump();
  }

  Future<void> flushExit(WidgetTester tester, bool Function() accepted) async {
    for (var i = 0; i < 3 && !accepted(); i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(nativeCalls.where((call) => call.method == 'close'), hasLength(1));
    expect(accepted(), isTrue);
  }

  testWidgets('records valid native client sizes independently of grid sizes', (
    tester,
  ) async {
    final app = await mount(tester);
    for (final arguments in [
      [920, 670],
      [935.0, 688.5],
      [0, 400],
      [1000, double.infinity],
      [900],
    ]) {
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('window_size_changed', arguments),
        ),
        null,
      );
    }
    expect(app.windowSizes, [(920, 670), (935, 689)]);
  });

  testWidgets('starts once after fonts and the viewport are ready', (
    tester,
  ) async {
    final fonts = Completer<List<String>>();
    platform.fontGate = fonts;
    final app = await mount(tester);
    expect(app.starts, isEmpty);
    await emit(
      tester,
      app,
      update(
        'ready',
        fonts: [const DisplayFont(family: 'monospace', size: 14)],
      ),
    );
    expect(app.starts, isEmpty);
    fonts.complete(['monospace']);
    await tester.pump();
    await tester.pump();
    expect(app.starts, hasLength(1));
    expect(app.starts.single.$1, greaterThan(0));
    expect(app.starts.single.$2, greaterThan(0));
    await emit(tester, app, update('ready'));
    await emit(tester, app, update('welcome'));
    expect(app.starts, hasLength(1));
    expect(app.connections, isEmpty);
    expect(app.defaults, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keeps the default local destination separate from the local alias',
    (tester) async {
      final app = await mount(tester);
      await emit(tester, app, update('ready', hosts: ['local']));
      await tester.tap(find.text('Default local host'));
      await tester.pump();
      expect(app.defaults, hasLength(1));
      expect(app.connections, isEmpty);
      await emit(tester, app, update('welcome'));
      await tester.tap(find.widgetWithText(ListTile, 'local'));
      await tester.pump();
      expect(app.connections, hasLength(1));
      expect(app.connections.single.$1, 'local');
      expect(app.defaults, hasLength(1));
      expect(find.text('Cancel connection'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancel connection'));
      await tester.pump();
      await tester.tap(find.text('Cancel connection'));
      await tester.pump();
      expect(app.detaches, 1);
    },
  );

  testWidgets(
    'lists tabpages once and removes closed tabs with retained buffers',
    (tester) async {
      final app = await mount(tester);
      await emit(tester, app, update('ready'));

      Future<void> tabline(List<String> names, List<int> handles) => emit(
        tester,
        app,
        update(
          'frame',
          frame: frame(
            widgets: [
              widget('tabs', items: names, handles: handles),
              widget(
                'buffers',
                items: ['[No Name]', 'checkhealth'],
                handles: [10, 20],
              ),
            ],
          ),
        ),
      );

      await tabline(['[No Name]'], [100]);
      expect(find.text('[No Name]'), findsOneWidget);
      expect(find.text('checkhealth'), findsNothing);

      await tabline(['[No Name]', 'checkhealth'], [100, 200]);
      expect(find.text('[No Name]'), findsOneWidget);
      expect(find.text('checkhealth'), findsOneWidget);
      await tester.tap(find.text('checkhealth'));
      await tester.pump();
      expect(app.tabpages, [200]);
      expect(app.buffers, isEmpty);

      await tabline(['[No Name]'], [100]);
      expect(find.text('[No Name]'), findsOneWidget);
      expect(find.text('checkhealth'), findsNothing);

      // Equal labels still represent two tabs when their handles differ.
      await tabline(['[No Name]', '[No Name]'], [100, 300]);
      expect(find.text('[No Name]'), findsNWidgets(2));
      await tester.tap(find.text('[No Name]').last);
      await tester.pump();
      expect(app.tabpages, [200, 300]);
      expect(app.buffers, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('uses tabpage handles and completion indices for GUI actions', (
    tester,
  ) async {
    final app = await mount(tester);
    await emit(tester, app, update('ready'));
    await emit(
      tester,
      app,
      update(
        'frame',
        frame: frame(
          widgets: [
            widget(
              'tabs',
              items: ['First tab', 'Second tab'],
              handles: [101, 202],
            ),
            widget('buffers', items: ['Buffer file'], handles: [303]),
            widget(
              'cmdline',
              chunks: [const DisplayChunk(text: ':界', highlight: 0)],
            ),
            widget('popup', items: ['alpha', 'beta']),
          ],
        ),
      ),
    );
    expect(find.byType(CommandLine), findsOneWidget);
    expect(
      tester
          .widget<CommandLine>(find.byType(CommandLine))
          .item
          .chunks
          .single
          .text,
      ':界',
    );
    await tester.tap(find.text('Second tab'));
    await tester.pump();
    expect(find.text('Buffer file'), findsNothing);
    await tester.tap(find.text('beta'));
    await tester.pump();
    expect(app.tabpages, [202]);
    expect(app.buffers, isEmpty);
    expect(app.completions, [1]);
    expect(app.inputs, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'defers previews until their grid arrives and clears them on welcome',
    (tester) async {
      final app = await mount(tester);
      await emit(tester, app, update('ready'));
      const preview = DisplayWindow(
        handle: 47,
        url: 'https://localhost:1234/preview#section',
        grid: 2,
        top: 2,
        left: 1,
        height: 3,
        width: 5,
        focus: false,
        focusable: true,
        closeOnBlur: false,
        replaceHistory: false,
      );
      await emit(tester, app, update('open_webview', window: preview));
      await emit(tester, app, update('close_webview', window: preview));
      expect(
        nativeCalls.where((call) => call.method == 'open_webview'),
        isEmpty,
      );
      await emit(
        tester,
        app,
        update('frame', frame: frame(grids: [grid(1), grid(2)])),
      );
      final opens = nativeCalls
          .where((call) => call.method == 'open_webview')
          .toList();
      expect(opens, hasLength(1));
      final arguments = opens.single.arguments as Map;
      expect(arguments['handle'], 47);
      expect(arguments['url'], preview.url);
      expect(arguments['width'], greaterThan(0));
      expect(arguments['height'], greaterThan(0));
      expect(arguments['key_bindings'], [
        {'key': 'r', 'modifiers': 1, 'action': 'reload'},
        {'key': 'w', 'modifiers': 1, 'action': 'close'},
        {'key': 'escape', 'modifiers': 0, 'action': 'focusEditor'},
      ]);
      await emit(tester, app, update('welcome'));
      final closed = nativeCalls.where(
        (call) => call.method == 'close_webview',
      );
      expect(closed.map((call) => (call.arguments as Map)['handle']), [47]);
      await emit(
        tester,
        app,
        update('frame', frame: frame(grids: [grid(1), grid(2)])),
      );
      expect(
        nativeCalls.where((call) => call.method == 'open_webview'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'routes the paste shortcut directly to the engine clipboard action',
    (tester) async {
      final app = await mount(tester);
      await emit(tester, app, update('ready'));
      await emit(tester, app, update('frame', frame: frame()));
      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      if (defaultTargetPlatform != TargetPlatform.macOS) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      if (defaultTargetPlatform != TargetPlatform.macOS) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(app.pastes, 1);
      expect(app.inputs, isEmpty);
    },
  );

  testWidgets('handles ordered frame events once and retains client errors', (
    tester,
  ) async {
    final app = await mount(tester);
    await emit(tester, app, update('ready'));
    final next = frame(
      events: [
        const DisplayEvent(kind: 'title', text: 'notes.txt — Nauvim'),
        const DisplayEvent(kind: 'error', text: 'Host command failed'),
      ],
    );
    await emit(tester, app, update('frame', frame: next));
    expect(find.text('Host command failed'), findsOneWidget);
    expect(nativeCalls.where((call) => call.method == 'title'), hasLength(1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(nativeCalls.where((call) => call.method == 'title'), hasLength(1));
    await emit(tester, app, update('frame', frame: next));
    final titles = nativeCalls.where((call) => call.method == 'title').toList();
    expect(titles, hasLength(2));
    expect((titles.first.arguments as Map)['title'], 'notes.txt — Nauvim');
    await emit(tester, app, update('welcome'));
    expect(find.text('Host command failed'), findsOneWidget);
  });

  testWidgets('drains final diagnostics before closing the native window', (
    tester,
  ) async {
    final app = await mount(tester);
    await emit(tester, app, update('ready'));
    final observer =
        tester.state(find.byType(NauvimHeadless)) as WidgetsBindingObserver;
    var accepted = false;
    final response = observer.didRequestAppExit().then((_) => accepted = true);
    await tester.pump();
    expect(app.closes, 1);
    expect(app.controller.hasListener, isTrue);
    expect(nativeCalls.where((call) => call.method == 'close'), isEmpty);
    expect(accepted, isFalse);
    await emit(
      tester,
      app,
      update('error', message: 'Remove process temporary directory: denied'),
    );
    expect(
      find.text('Remove process temporary directory: denied'),
      findsOneWidget,
    );
    expect(nativeCalls.where((call) => call.method == 'close'), isEmpty);
    await emit(tester, app, update('shutdown'));
    await flushExit(tester, () => accepted);
    await response;
    expect(
      find.text('Remove process temporary directory: denied'),
      findsOneWidget,
    );
  });

  for (final terminal in ['done', 'error']) {
    testWidgets('closes after the engine stream terminates with $terminal', (
      tester,
    ) async {
      final app = await mount(tester);
      if (terminal == 'done') {
        unawaited(app.controller.close());
      } else {
        app.controller.addError(StateError('Engine initialization failed'));
      }
      await tester.pump();
      final observer =
          tester.state(find.byType(NauvimHeadless)) as WidgetsBindingObserver;
      var accepted = false;
      final response = observer.didRequestAppExit().then(
        (_) => accepted = true,
      );
      await flushExit(tester, () => accepted);
      await response;
      expect(app.closes, 1);
      if (terminal == 'error') {
        expect(
          find.textContaining('Engine initialization failed'),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('closes after startup fails before an engine exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      const NauvimApp(startupError: 'Native engine unavailable'),
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final observer =
        tester.state(find.byType(NauvimHeadless)) as WidgetsBindingObserver;
    var accepted = false;
    final response = observer.didRequestAppExit().then((_) => accepted = true);
    await flushExit(tester, () => accepted);
    await response;
    expect(find.text('Native engine unavailable'), findsOneWidget);
  });
}

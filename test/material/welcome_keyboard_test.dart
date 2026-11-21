import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nauvim_flutter/nauvim.dart';
import 'package:nauvim_flutter/nauvim_material.dart';

import '../support/fakes.dart';

Future<({FakeEngine engine, NauvimController controller})> welcome(
  WidgetTester tester, {
  bool ready = true,
  List<String> hosts = const ['local', 'work'],
  FakePlatform? platform,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  final engine = FakeEngine();
  final controller = NauvimController(
    engine: engine,
    platform: platform ?? FakePlatform(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await engine.events.close();
    debugDefaultTargetPlatformOverride = null;
  });
  await tester.pumpWidget(NauvimMaterialApp(controller: controller));
  if (ready) {
    engine.emit(UiUpdate(kind: 'ready', hosts: hosts, fonts: const []));
  }
  await tester.pump();
  await tester.pump();
  return (engine: engine, controller: controller);
}

String selectedItem(WidgetTester tester) =>
    (tester
                .widgetList<ListTile>(find.byType(ListTile))
                .singleWhere((item) => item.selected)
                .title!
            as Text)
        .data!;

TextField hostField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

Future<void> controlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> shiftTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

Future<void> returnToWelcome(WidgetTester tester, FakeEngine engine) async {
  engine.emit(const UiUpdate(kind: 'welcome', hosts: [], fonts: []));
  await tester.pump();
  await tester.pump();
}

Future<void> finishQuit(WidgetTester tester, FakePlatform platform) async {
  for (var i = 0; i < 3 && platform.closes == 0; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  expect(platform.closes, 1);
}

Future<void> manualEntry(WidgetTester tester) async {
  final count = tester.widgetList<ListTile>(find.byType(ListTile)).length;
  for (
    var index = 0;
    index < count && selectedItem(tester) != 'Type yourself';
    index++
  ) {
    await key(tester, LogicalKeyboardKey.keyJ);
  }
  expect(selectedItem(tester), 'Type yourself');
  await key(tester, LogicalKeyboardKey.enter);
  await tester.pump();
}

void main() {
  testWidgets('starts in selection mode and activates only when ready', (
    tester,
  ) async {
    final (:engine, :controller) = await welcome(tester, ready: false);
    expect(find.byType(TextField), findsNothing);
    expect(selectedItem(tester), 'Default local host');
    await key(tester, LogicalKeyboardKey.enter);
    expect(engine.defaults, isEmpty);
    expect(engine.connections, isEmpty);

    engine.emit(const UiUpdate(kind: 'ready', hosts: ['local'], fonts: []));
    await tester.pump();
    await tester.pump();
    await key(tester, LogicalKeyboardKey.enter);
    expect(engine.defaults, hasLength(1));
    expect(engine.connections, isEmpty);
    expect(controller.connecting, isTrue);
    await key(tester, LogicalKeyboardKey.enter);
    expect(engine.defaults, hasLength(1));
    await key(tester, LogicalKeyboardKey.escape);
    expect(engine.detaches, 1);

    await returnToWelcome(tester, engine);
    expect(find.byType(TextField), findsNothing);
    expect(selectedItem(tester), 'Default local host');
    await key(tester, LogicalKeyboardKey.enter);
    expect(engine.defaults, hasLength(2));
  });

  testWidgets('navigates vertically with jk and keeps named local distinct', (
    tester,
  ) async {
    final (:engine, :controller) = await welcome(tester);
    expect(selectedItem(tester), 'Default local host');
    await key(tester, LogicalKeyboardKey.keyJ);
    expect(selectedItem(tester), 'local');
    await key(tester, LogicalKeyboardKey.keyL);
    expect(selectedItem(tester), 'local');
    await key(tester, LogicalKeyboardKey.keyH);
    expect(selectedItem(tester), 'local');
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(selectedItem(tester), 'local');
    await key(tester, LogicalKeyboardKey.keyJ);
    expect(selectedItem(tester), 'work');
    await key(tester, LogicalKeyboardKey.keyK);
    expect(selectedItem(tester), 'local');
    await key(tester, LogicalKeyboardKey.keyK);
    expect(selectedItem(tester), 'Default local host');
    await controlKey(tester, LogicalKeyboardKey.keyN);
    expect(selectedItem(tester), 'local');
    await controlKey(tester, LogicalKeyboardKey.keyP);
    expect(selectedItem(tester), 'Default local host');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(selectedItem(tester), 'local');
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(selectedItem(tester), 'Default local host');
    await key(tester, LogicalKeyboardKey.tab);
    expect(selectedItem(tester), 'local');
    await shiftTab(tester);
    expect(selectedItem(tester), 'Default local host');
    expect(engine.connections, isEmpty);
    expect(engine.defaults, isEmpty);
    expect(find.byType(TextField), findsNothing);

    await key(tester, LogicalKeyboardKey.keyJ);
    await key(tester, LogicalKeyboardKey.enter);
    expect(engine.connections.single.$1, 'local');
    expect(engine.defaults, isEmpty);
    expect(controller.destination, 'local');
  });

  testWidgets('restores the destination after leaving an attached editor', (
    tester,
  ) async {
    final (:engine, :controller) = await welcome(
      tester,
      hosts: ['local', 'Local', 'default'],
    );
    for (final detach in [false, true]) {
      for (final alias in [null, 'local', 'Local', 'default', 'manual-host']) {
        final title = alias == null
            ? 'Default local host'
            : alias == 'manual-host'
            ? 'Type yourself'
            : alias;
        await tester.tap(find.widgetWithText(ListTile, title));
        await tester.pump();
        if (alias == 'manual-host') {
          tester.testTextInput.enterText(alias!);
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();
        }
        engine.emit(
          UiUpdate(
            kind: 'connecting',
            message: alias ?? 'Local',
            destination: DisplayDestination(alias: alias),
            hosts: const [],
            fonts: const [],
          ),
        );
        engine.emit(
          const UiUpdate(
            kind: 'frame',
            frame: DisplayFrame(
              full: true,
              grids: [],
              removedGrids: [],
              rows: [],
              highlights: [],
              title: '',
              mode: 'normal',
              busy: false,
              events: [],
            ),
            hosts: [],
            fonts: [],
          ),
        );
        await tester.pump();
        expect(controller.attached, isTrue);
        expect(find.byType(ListTile), findsNothing);
        if (detach) await controller.detach();
        await returnToWelcome(tester, engine);
        expect(selectedItem(tester), title);
        expect(controller.destination, alias ?? '');
        expect(find.byType(TextField), findsNothing);
      }
    }
    expect(engine.detaches, 5);
    expect(tester.takeException(), isNull);
  });

  for (final alias in [null, 'local', 'Local', 'default', 'manual-host']) {
    testWidgets('restores the saved destination $alias when ready arrives', (
      tester,
    ) async {
      final (:engine, :controller) = await welcome(tester, ready: false);
      engine.emit(
        UiUpdate(
          kind: 'ready',
          destination: DisplayDestination(alias: alias),
          hosts: const ['local', 'Local', 'default'],
          fonts: const [],
        ),
      );
      await tester.pump();
      await tester.pump();
      final title = alias == null
          ? 'Default local host'
          : alias == 'manual-host'
          ? 'Type yourself'
          : alias;
      expect(selectedItem(tester), title);
      expect(find.byType(TextField), findsNothing);
      expect(controller.connecting, isFalse);
      expect(engine.defaults, isEmpty);
      expect(engine.connections, isEmpty);
      await key(tester, LogicalKeyboardKey.enter);
      if (alias == 'manual-host') {
        expect(hostField(tester).controller!.text, alias);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
      }
      if (alias == null) {
        expect(engine.defaults, hasLength(1));
        expect(engine.connections, isEmpty);
      } else {
        expect(engine.connections.single.$1, alias);
        expect(engine.defaults, isEmpty);
      }
    });
  }

  testWidgets('Type yourself enters text mode and Escape retains its draft', (
    tester,
  ) async {
    final (:engine, :controller) = await welcome(tester);
    await manualEntry(tester);
    expect(hostField(tester).focusNode!.hasFocus, isTrue);
    expect(engine.connections, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(engine.defaults, isEmpty);
    expect(engine.connections, isEmpty);

    const letters = [
      (LogicalKeyboardKey.keyH, 'h'),
      (LogicalKeyboardKey.keyJ, 'j'),
      (LogicalKeyboardKey.keyK, 'k'),
      (LogicalKeyboardKey.keyL, 'l'),
    ];
    var draft = '';
    for (final (key, letter) in letters) {
      expect(await tester.sendKeyEvent(key), isFalse);
      draft += letter;
      tester.testTextInput.enterText(draft);
      await tester.pump();
      expect(hostField(tester).controller!.text, draft);
    }
    await controlKey(tester, LogicalKeyboardKey.keyN);
    await controlKey(tester, LogicalKeyboardKey.keyP);
    expect(hostField(tester).focusNode!.hasFocus, isTrue);
    expect(hostField(tester).controller!.text, 'hjkl');
    tester.testTextInput.enterText('hjkl');
    await tester.pump();
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(hostField(tester).controller!.selection.baseOffset, 3);
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(TextField), findsNothing);
    expect(selectedItem(tester), 'Type yourself');

    await key(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(hostField(tester).focusNode!.hasFocus, isTrue);
    expect(hostField(tester).controller!.text, 'hjkl');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(engine.connections.single.$1, 'hjkl');
    expect(controller.connecting, isTrue);
  });

  testWidgets('keeps manual drafts through traversal and connection failures', (
    tester,
  ) async {
    final (:engine, :controller) = await welcome(tester);
    await manualEntry(tester);
    tester.testTextInput.enterText('draft-host');
    await tester.pump();
    await key(tester, LogicalKeyboardKey.tab);
    expect(hostField(tester).focusNode!.hasFocus, isFalse);
    final focusedControl = FocusManager.instance.primaryFocus;
    controller.reportError('Unrelated diagnostic');
    await tester.pump();
    expect(hostField(tester).controller!.text, 'draft-host');
    expect(FocusManager.instance.primaryFocus, same(focusedControl));
    await shiftTab(tester);
    expect(hostField(tester).focusNode!.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.escape);
    expect(selectedItem(tester), 'Type yourself');

    await key(tester, LogicalKeyboardKey.keyK);
    expect(selectedItem(tester), 'work');
    await key(tester, LogicalKeyboardKey.enter);
    expect(engine.connections.single.$1, 'work');
    await key(tester, LogicalKeyboardKey.escape);
    expect(engine.detaches, 1);
    engine.emit(
      const UiUpdate(
        kind: 'welcome',
        message: 'Connection failed',
        hosts: [],
        fonts: [],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(selectedItem(tester), 'work');
    await key(tester, LogicalKeyboardKey.keyJ);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(hostField(tester).focusNode!.hasFocus, isTrue);
    expect(hostField(tester).controller!.text, 'draft-host');
    expect(tester.takeException(), isNull);
  });

  testWidgets('q closes the application even while a connection is pending', (
    tester,
  ) async {
    final platform = FakePlatform();
    final (:engine, :controller) = await welcome(tester, platform: platform);
    await key(tester, LogicalKeyboardKey.enter);
    expect(controller.connecting, isTrue);
    await key(tester, LogicalKeyboardKey.keyQ);
    await finishQuit(tester, platform);
    expect(controller.closing, isTrue);
    expect(engine.closes, 1);
    expect(engine.detaches, 0);
    expect(platform.closes, 1);
  });

  testWidgets(
    'q is text in manual entry and quits after returning to the menu',
    (tester) async {
      final platform = FakePlatform();
      final (:engine, :controller) = await welcome(tester, platform: platform);
      await manualEntry(tester);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyQ), isFalse);
      tester.testTextInput.enterText('quiet-host');
      await tester.pump();
      expect(hostField(tester).controller!.text, 'quiet-host');
      expect(engine.closes, 0);
      expect(platform.closes, 0);
      await key(tester, LogicalKeyboardKey.escape);
      await key(tester, LogicalKeyboardKey.keyQ);
      await finishQuit(tester, platform);
      expect(controller.closing, isTrue);
      expect(engine.closes, 1);
      expect(platform.closes, 1);
    },
  );

  testWidgets('scrolls the selected destination into view in a long menu', (
    tester,
  ) async {
    final hosts = List.generate(30, (index) => 'host-$index');
    final (:engine, :controller) = await welcome(tester, hosts: hosts);
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, 0);
    await key(tester, LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(selectedItem(tester), 'host-0');
    expect(scrollable.position.pixels, 0);
    for (var index = 1; index < hosts.length + 1; index++) {
      await key(tester, LogicalKeyboardKey.keyJ);
    }
    await tester.pumpAndSettle();
    expect(selectedItem(tester), 'Type yourself');
    final selected = tester.getRect(
      find.widgetWithText(ListTile, 'Type yourself'),
    );
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    expect(selected.top, greaterThanOrEqualTo(viewport.top));
    expect(selected.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(engine.connections, isEmpty);
    expect(controller.connecting, isFalse);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(hostField(tester).focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores a selected host into view when welcome remounts', (
    tester,
  ) async {
    final hosts = List.generate(30, (index) => 'host-$index');
    final (:engine, :controller) = await welcome(tester, hosts: hosts);
    await controller.connect(hosts.last);
    await returnToWelcome(tester, engine);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(NauvimMaterialApp(controller: controller));
    await tester.pumpAndSettle();
    expect(selectedItem(tester), hosts.last);
    expect(find.byType(TextField), findsNothing);
    final selected = tester.getRect(find.widgetWithText(ListTile, hosts.last));
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    expect(selected.top, greaterThanOrEqualTo(viewport.top));
    expect(selected.bottom, lessThanOrEqualTo(viewport.bottom));
    await key(tester, LogicalKeyboardKey.keyJ);
    expect(selectedItem(tester), 'Type yourself');
    expect(tester.takeException(), isNull);
  });
}

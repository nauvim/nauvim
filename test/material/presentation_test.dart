import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nauvim_flutter/nauvim.dart';
import 'package:nauvim_flutter/nauvim_material.dart';
import 'package:nauvim_flutter/nauvim_widgets.dart';

import '../support/fakes.dart';

DisplayFrame editorFrame({
  int? foreground = 0xffffff,
  int? background = 0x15181e,
  List<DisplayWidget> widgets = const [],
  int gridHeight = 1,
}) => DisplayFrame(
  full: true,
  grids: [
    DisplayGrid(
      id: 1,
      width: 3,
      height: gridHeight,
      row: 0,
      col: 0,
      zindex: 0,
      order: 0,
      hidden: false,
    ),
  ],
  removedGrids: [],
  rows: [
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
  highlights: [],
  foreground: foreground,
  background: background,
  title: '',
  mode: 'normal',
  busy: false,
  widgets: widgets,
  events: const [],
);

class CompletionEngine extends FakeEngine {
  final completions = <int>[];
  @override
  Future<void> selectPopupmenuItem({required int index}) async =>
      completions.add(index);
}

void main() {
  testWidgets(
    'expands and scrolls bottom messages while keeping the command row anchored',
    (tester) async {
      final engine = CompletionEngine();
      final controller = NauvimController(
        engine: engine,
        platform: FakePlatform(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await engine.events.close();
      });
      await tester.pumpWidget(NauvimMaterialApp(controller: controller));
      engine.emit(const UiUpdate(kind: 'ready', hosts: [], fonts: []));
      await tester.pump();
      await tester.pump();

      Future<void> display(List<DisplayWidget> widgets) async {
        engine.emit(
          UiUpdate(
            kind: 'frame',
            frame: editorFrame(widgets: widgets),
            hosts: const [],
            fonts: const [],
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
      }

      DisplayWidget text(String kind, String value) => DisplayWidget(
        kind: kind,
        grid: 1,
        row: 0,
        col: 0,
        selected: value.length,
        chunks: [DisplayChunk(text: value, highlight: 0)],
        items: const [],
        handles: const [],
      );

      final surface = find.byType(EditorSurface);
      final indicators = find.descendant(
        of: find.byType(NauvimStatus),
        matching: find.byType(RichText),
      );
      await display([]);
      final editorBounds = tester.getRect(surface);
      final presentationBounds = tester.getRect(find.byType(NauvimEditor));
      final editorRows = controller.viewport!.rows;
      expect(editorBounds.bottom, lessThan(presentationBounds.bottom));
      final resizes = List.of(engine.resizes);
      void expectStableViewport() {
        expect(tester.getRect(surface), editorBounds);
        expect(controller.viewport!.rows, editorRows);
        expect(engine.resizes, resizes);
      }

      await display([text('status', 'g')]);
      expectStableViewport();
      expect(tester.widget<RichText>(indicators).text.toPlainText(), 'g');
      expect(
        tester
            .getRect(find.byType(NauvimToolbar))
            .contains(tester.getCenter(indicators)),
        isTrue,
      );

      await display([
        text('status', '-- NORMAL --'),
        text('status', 'g'),
        text('status', '1,1'),
      ]);
      expectStableViewport();
      expect(
        tester.widget<RichText>(indicators).text.toPlainText(),
        '-- NORMAL --  g  1,1',
      );

      final command = text('cmdline', ':checkhealth');
      await display([command]);
      expectStableViewport();
      final commandBounds = tester.getRect(find.byType(CommandLine));
      expect(commandBounds.top, greaterThanOrEqualTo(editorBounds.bottom));
      expect(
        commandBounds.bottom,
        lessThanOrEqualTo(presentationBounds.bottom),
      );
      final panel = find
          .ancestor(
            of: find.byType(CommandLine),
            matching: find.byType(ColoredBox),
          )
          .first;
      final panelBounds = tester.getRect(panel);
      expect(panelBounds.left, editorBounds.left);
      expect(panelBounds.right, editorBounds.right);
      expect(panelBounds.bottom, presentationBounds.bottom);
      expect(panelBounds.top, greaterThanOrEqualTo(editorBounds.bottom));
      expect(panelBounds.top, editorBounds.bottom);
      expect(panelBounds.height, controller.viewport!.cellHeight);
      expect(
        controller.viewport!.size.width,
        controller.viewport!.columns * controller.viewport!.cellWidth,
      );
      expect(
        controller.viewport!.size.height,
        controller.viewport!.rows * controller.viewport!.cellHeight,
      );
      expect(tester.widget<ColoredBox>(panel).color, const Color(0xff15181e));
      await display([command, text('status', ':')]);
      expectStableViewport();
      expect(find.byType(CommandLine), findsOneWidget);
      expect(indicators, findsNothing);

      await display([
        command,
        const DisplayWidget(
          kind: 'cmdline_popup',
          grid: 1,
          row: 0,
          col: 1,
          selected: 0,
          chunks: [],
          items: ['checkhealth', 'checktime'],
          handles: [],
        ),
      ]);
      expectStableViewport();
      final menuBounds = tester.getRect(find.byType(NauvimCompletionMenu));
      expect(menuBounds.top, greaterThanOrEqualTo(editorBounds.top));
      expect(menuBounds.bottom, lessThanOrEqualTo(commandBounds.top));
      await tester.tap(find.text('checktime'));
      await tester.pump();
      expect(engine.completions, [1]);

      const undo = '1 line less; before #1 2 seconds ago';
      await display([text('message', undo)]);
      expectStableViewport();
      expect(find.byType(CommandLine), findsNothing);
      expect(find.byType(NauvimCompletionMenu), findsNothing);
      final messageBounds = tester.getRect(find.text(undo, findRichText: true));
      expect(messageBounds.top, greaterThanOrEqualTo(editorBounds.bottom));
      expect(
        messageBounds.bottom,
        lessThanOrEqualTo(presentationBounds.bottom),
      );

      const error = 'Error in command line:\nE492: Not an editor command';
      const notification = 'Build finished';
      final errorText = find.text(error, findRichText: true);
      final notificationText = find.text(notification, findRichText: true);
      final messageScroll = find.ancestor(
        of: notificationText,
        matching: find.byType(Scrollable),
      );
      await display([text('message', error), text('message', notification)]);
      expectStableViewport();
      final expanded = tester.getRect(messageScroll);
      expect(expanded.bottom, panelBounds.bottom);
      expect(expanded.top, lessThan(panelBounds.top));
      expect(expanded.top, greaterThan(editorBounds.top));
      expect(tester.getRect(errorText).top, greaterThanOrEqualTo(expanded.top));
      expect(tester.getRect(notificationText).bottom, messageBounds.bottom);
      expect(
        tester.state<ScrollableState>(messageScroll).position.maxScrollExtent,
        0,
      );

      final multiline = List.filled(80, 'A line of message output').join('\n');
      await display([
        text('message', error),
        text('message', multiline),
        text('message', notification),
      ]);
      expectStableViewport();
      final capped = tester.getRect(messageScroll);
      expect(capped.top, editorBounds.top);
      expect(capped.bottom, panelBounds.bottom);
      expect(capped.contains(tester.getCenter(errorText)), isFalse);
      expect(tester.getRect(notificationText).bottom, messageBounds.bottom);

      final scroll = tester.state<ScrollableState>(messageScroll).position;
      expect(scroll.maxScrollExtent, greaterThan(0));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: capped.center,
          scrollDelta: Offset(0, -scroll.maxScrollExtent),
        ),
      );
      await tester.pump();
      expect(capped.contains(tester.getCenter(errorText)), isTrue);
      expect(capped.contains(tester.getCenter(notificationText)), isFalse);

      await display([]);
      expectStableViewport();
      expect(indicators, findsNothing);
      expect(errorText, findsNothing);
      expect(notificationText, findsNothing);
      final bottomScroll = find.descendant(
        of: find.byType(NauvimEditor),
        matching: find.byType(Scrollable),
      );
      expect(tester.getRect(bottomScroll), panelBounds);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changes the theme without replacing editor state or session logic',
    (tester) async {
      final engine = FakeEngine();
      final controller = NauvimController(
        engine: engine,
        platform: FakePlatform(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await engine.events.close();
      });
      await tester.pumpWidget(NauvimMaterialApp(controller: controller));
      engine.emit(const UiUpdate(kind: 'ready', hosts: [], fonts: []));
      await tester.pump();
      await tester.pump();
      engine.emit(
        UiUpdate(
          kind: 'frame',
          frame: editorFrame(),
          hosts: const [],
          fonts: const [],
        ),
      );
      await tester.pump();
      await tester.pump();
      final rows = controller.editor.grids[1]!.rows[0];
      final previousCellHeight = controller.viewport!.cellHeight;
      final appearance = const NauvimTheme().copyWith(
        toolbarHeight: 64,
        toolbarPadding: const EdgeInsets.symmetric(horizontal: 32),
        selectedTabColor: const Color(0xff112233),
        selectionColor: const Color(0x99667788),
        cursorColor: const Color(0xffaabbcc),
        cursorOpacity: 0.7,
        editorMetrics: const EditorMetricsStyle(
          lineHeight: 1.4,
          cellHeightMultiplier: 1.3,
        ),
      );
      await tester.pumpWidget(
        NauvimMaterialApp(
          controller: controller,
          theme: defaultNauvimTheme().copyWith(extensions: [appearance]),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final toolbar = tester.getSize(find.byType(NauvimToolbar));
      expect(toolbar.height, 64);
      final surface = tester.widget<EditorSurface>(find.byType(EditorSurface));
      expect(surface.style.selectionColor, appearance.selectionColor);
      expect(surface.style.cursorColor, appearance.cursorColor);
      expect(surface.style.cursorOpacity, appearance.cursorOpacity);
      expect(surface.metrics.lineHeight, appearance.editorMetrics.lineHeight);
      expect(controller.viewport!.cellHeight, greaterThan(previousCellHeight));
      expect(identical(controller.editor.grids[1]!.rows[0], rows), isTrue);
      expect(controller.attached, isTrue);
      expect(engine.starts, hasLength(1));
      controller.sendKeys('ihello<Esc>');
      await tester.pump();
      expect(engine.inputs, ['ihello<Esc>']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replaces visual sections while preserving their shared controller',
    (tester) async {
      final engine = FakeEngine();
      final platform = FakePlatform();
      final controller = NauvimController(engine: engine, platform: platform);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await engine.events.close();
      });
      await tester.pumpWidget(
        NauvimMaterialApp(
          controller: controller,
          windowBuilder: (context, session) => NauvimWindow(
            controller: session,
            toolbarBuilder: (context, session) =>
                const SizedBox(height: 52, child: Text('Custom toolbar')),
            errorBuilder: (context, session) =>
                Text('Error: ${session.errors.join(', ')}'),
            welcomeBuilder: (context, session) => TextButton(
              onPressed: session.connectDefault,
              child: const Text('Start from custom welcome'),
            ),
            editorBuilder: (context, session) =>
                const Center(child: Text('Custom editor arrangement')),
          ),
        ),
      );
      engine.emit(const UiUpdate(kind: 'ready', hosts: [], fonts: []));
      await tester.pump();
      await tester.pump();
      expect(find.text('Custom toolbar'), findsOneWidget);
      expect(find.byType(NauvimToolbar), findsNothing);
      expect(find.byType(NauvimWelcome), findsNothing);
      await tester.tap(find.text('Start from custom welcome'));
      await tester.pump();
      expect(engine.defaults, hasLength(1));
      engine.emit(
        UiUpdate(
          kind: 'frame',
          frame: editorFrame(),
          hosts: const [],
          fonts: const [],
        ),
      );
      await tester.pump();
      expect(find.text('Custom editor arrangement'), findsOneWidget);
      expect(find.byType(NauvimEditor), findsNothing);
      controller.reportError('Visible from every design');
      await tester.pump();
      expect(find.text('Error: Visible from every design'), findsOneWidget);
      expect(find.byType(NauvimErrorBanner), findsNothing);
      expect(controller.attached, isTrue);
      expect(platform.titles, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps a draft alias through unrelated state notifications', (
    tester,
  ) async {
    final engine = FakeEngine();
    final controller = NauvimController(
      engine: engine,
      platform: FakePlatform(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await engine.events.close();
    });
    await tester.pumpWidget(NauvimMaterialApp(controller: controller));
    engine.emit(const UiUpdate(kind: 'ready', hosts: [], fonts: []));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Type yourself'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'editing-alias');
    controller.reportError('An unrelated diagnostic');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'editing-alias',
    );
    await tester.ensureVisible(find.text('Connect to alias'));
    await tester.tap(find.text('Connect to alias'));
    await tester.pump();
    expect(engine.connections.single.$1, 'editing-alias');
    expect(tester.takeException(), isNull);
  });

  testWidgets('applies theme fallbacks without replacing raw Neovim colors', (
    tester,
  ) async {
    final engine = FakeEngine();
    final controller = NauvimController(
      engine: engine,
      platform: FakePlatform(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await engine.events.close();
    });
    const appearance = NauvimTheme(
      editorForeground: Color(0xff102030),
      editorBackground: Color(0xff405060),
    );
    await tester.pumpWidget(
      NauvimMaterialApp(
        controller: controller,
        theme: defaultNauvimTheme().copyWith(extensions: [appearance]),
      ),
    );
    engine.emit(const UiUpdate(kind: 'ready', hosts: [], fonts: []));
    await tester.pump();
    await tester.pump();
    const widgets = [
      DisplayWidget(
        kind: 'cmdline',
        grid: 1,
        row: 0,
        col: 0,
        selected: 1,
        chunks: [DisplayChunk(text: ':', highlight: 0)],
        items: [],
        handles: [],
      ),
      DisplayWidget(
        kind: 'message',
        grid: 1,
        row: 0,
        col: 0,
        selected: -1,
        chunks: [DisplayChunk(text: 'notice', highlight: 0)],
        items: [],
        handles: [],
      ),
    ];
    final unspecified = editorFrame(
      foreground: null,
      background: null,
      widgets: widgets,
    );
    engine.emit(
      UiUpdate(
        kind: 'frame',
        frame: unspecified,
        hosts: const [],
        fonts: const [],
      ),
    );
    await tester.pump();
    await tester.pump();
    final surface = tester.widget<EditorSurface>(find.byType(EditorSurface));
    final command = tester.widget<CommandLine>(find.byType(CommandLine));
    expect(surface.style.fallbackForeground, appearance.editorForeground);
    expect(surface.style.fallbackBackground, appearance.editorBackground);
    expect(command.paintStyle.fallbackForeground, appearance.editorForeground);
    expect(command.paintStyle.fallbackBackground, appearance.editorBackground);
    TextStyle? styleFor(InlineSpan span) {
      if (span is! TextSpan) return null;
      if (span.text == 'notice') return span.style;
      for (final child in span.children ?? const <InlineSpan>[]) {
        final style = styleFor(child);
        if (style != null) return style;
      }
      return null;
    }

    TextStyle noticeStyle() => tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => styleFor(text.text))
        .whereType<TextStyle>()
        .single;
    expect(noticeStyle().color, appearance.editorForeground);
    expect(noticeStyle().backgroundColor, appearance.editorBackground);
    expect(identical(controller.editor.frame, unspecified), isTrue);
    expect(controller.editor.frame!.foreground, isNull);
    expect(controller.editor.frame!.background, isNull);

    final explicit = editorFrame(
      foreground: 0xaabbcc,
      background: 0xddeeff,
      widgets: widgets,
    );
    engine.emit(
      UiUpdate(
        kind: 'frame',
        frame: explicit,
        hosts: const [],
        fonts: const [],
      ),
    );
    await tester.pump();
    expect(noticeStyle().color, const Color(0xffaabbcc));
    expect(noticeStyle().backgroundColor, const Color(0xffddeeff));
    expect(identical(controller.editor.frame, explicit), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'custom completion rows receive unchanged host fields and selection',
    (tester) async {
      const first = DisplayCompletion(
        word: '  α() ',
        kind: ' f ',
        menu: 'module  ',
        info: 'line one\n line two ',
      );
      const second = DisplayCompletion(
        word: 'β',
        kind: 'v',
        menu: 'meta',
        info: 'details',
      );
      const popup = DisplayWidget(
        kind: 'popup',
        grid: 1,
        row: 0,
        col: 0,
        selected: 1,
        chunks: [],
        items: [],
        handles: [],
        completions: [first, second],
      );
      final built = <(DisplayCompletion, bool)>[];
      final selected = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: NauvimCompletionMenu(
                  popup: popup,
                  style: const TextStyle(fontSize: 14),
                  onSelected: selected.add,
                  itemBuilder: (context, item, isSelected) {
                    built.add((item, isSelected));
                    return Text(
                      '${item.kind}|${item.menu}|${item.word}',
                      key: ValueKey(item.word),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        built.any((entry) => identical(entry.$1, first) && !entry.$2),
        isTrue,
      );
      expect(
        built.any((entry) => identical(entry.$1, second) && entry.$2),
        isTrue,
      );
      expect(find.text(' f |module  |  α() '), findsOneWidget);
      expect(
        tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((tip) => tip.message),
        contains(first.info),
      );
      await tester.tap(find.byKey(const ValueKey('β')));
      expect(selected, [1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom editor completion rows keep their measured menu inside the viewport',
    (tester) async {
      final engine = CompletionEngine();
      final controller = NauvimController(
        engine: engine,
        platform: FakePlatform(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await engine.events.close();
      });
      await tester.pumpWidget(
        NauvimMaterialApp(
          controller: controller,
          windowBuilder: (context, session) => NauvimWindow(
            controller: session,
            editorBuilder: (context, session) => NauvimEditor(
              controller: session,
              completionItemBuilder: (context, item, selected) => SizedBox(
                height: 72,
                child: Text(
                  '${item.menu} :: ${item.word}',
                  key: ValueKey(item.word),
                ),
              ),
            ),
          ),
        ),
      );
      engine.emit(const UiUpdate(kind: 'ready', hosts: [], fonts: []));
      await tester.pump();
      await tester.pump();
      final rows = controller.viewport!.rows;
      engine.emit(
        UiUpdate(
          kind: 'frame',
          hosts: const [],
          fonts: const [],
          frame: editorFrame(
            gridHeight: rows,
            widgets: [
              DisplayWidget(
                kind: 'popup',
                grid: 1,
                row: (rows - 1).toDouble(),
                col: 0,
                selected: 0,
                chunks: const [],
                items: const [],
                handles: const [],
                completions: const [
                  DisplayCompletion(
                    word: 'alpha',
                    kind: 'f',
                    menu: 'first',
                    info: '',
                  ),
                  DisplayCompletion(
                    word: 'beta',
                    kind: 'v',
                    menu: 'second',
                    info: '',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('first :: alpha'), findsOneWidget);
      final surface = tester.getRect(find.byType(EditorSurface));
      final menu = tester.getRect(find.byType(NauvimCompletionMenu));
      expect(menu.top, greaterThanOrEqualTo(surface.top));
      expect(menu.bottom, lessThanOrEqualTo(surface.bottom));
      await tester.tap(find.byKey(const ValueKey('beta')));
      await tester.pump();
      expect(engine.completions, [1]);
      expect(engine.inputs, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

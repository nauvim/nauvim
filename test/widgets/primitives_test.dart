import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nauvim_flutter/nauvim.dart';
import 'package:nauvim_flutter/nauvim_widgets.dart';

import '../support/fakes.dart';

DisplayFrame frame({
  String text = 'a',
  int? foreground = 0xffffff,
  int? background = 0,
}) => DisplayFrame(
  full: false,
  grids: const [
    DisplayGrid(
      id: 1,
      width: 20,
      height: 2,
      row: 0,
      col: 0,
      zindex: 0,
      order: 0,
      hidden: false,
    ),
  ],
  removedGrids: const [],
  rows: [
    DisplayRow(grid: 1, row: 0, cells: [DisplayCell(text: text, highlight: 0)]),
  ],
  highlights: const [],
  foreground: foreground,
  background: background,
  title: '',
  mode: 'normal',
  busy: false,
  widgets: const [],
  events: const [],
);

void main() {
  testWidgets(
    'includes window margins in the grid base and retains them on resize',
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
        Directionality(
          textDirection: TextDirection.ltr,
          child: EditorViewportRegion(
            controller: controller,
            bottomRows: 1,
            builder: (_, viewport) => const SizedBox.expand(),
          ),
        ),
      );
      engine.emit(
        const UiUpdate(
          kind: 'ready',
          windowOptions: DisplayWindowOptions(
            width: 960,
            height: 640,
            margin: DisplayMargins(top: 3, bottom: 5, left: 7, right: 11),
          ),
          fonts: [DisplayFont(family: 'monospace', size: 15)],
          hosts: [],
        ),
      );
      await tester.pump();
      await tester.pump();
      final before = controller.viewport!;
      expect(platform.initialWindows, hasLength(1));
      expect(platform.windowGrids.last.baseWidth, 18);
      expect(platform.windowGrids.last.baseHeight, 8);
      expect(before.origin.dx, 7);
      expect(before.size.width, before.columns * before.cellWidth);
      expect(before.size.height, before.rows * before.cellHeight);
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(
        before.origin.dy + before.size.height + before.cellHeight,
        size.height - 5,
      );
      tester.view.physicalSize =
          tester.view.physicalSize + const Offset(37, 29);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pump();
      await tester.pump();
      final after = controller.viewport!;
      expect(platform.initialWindows, hasLength(1));
      expect(platform.windowGrids.last.baseWidth, 18);
      expect(platform.windowGrids.last.baseHeight, 8);
      expect(after.origin.dx, 7);
      expect(after.size.width, after.columns * after.cellWidth);
      expect(after.size.height, after.rows * after.cellHeight);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('runs an editor without Material and isolates frame rebuilds', (
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
    var shellBuilds = 0;
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0x00000000),
        builder: (context, _) => NauvimHeadless(
          controller: controller,
          builder: (context, state) {
            shellBuilds++;
            return EditorSurface(
              controller: state,
              style: const EditorPaintStyle(selectionColor: Color(0x66334455)),
            );
          },
        ),
      ),
    );
    expect(engine.starts, isEmpty);
    engine.emit(
      const UiUpdate(
        kind: 'ready',
        hosts: [],
        fonts: [DisplayFont(family: 'monospace', size: 14)],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(engine.starts, hasLength(1));
    expect(identical(controller.viewport!.font, controller.font), isTrue);
    expect(controller.viewport!.cellWidth, greaterThan(0));
    engine.emit(
      UiUpdate(kind: 'frame', frame: frame(), hosts: const [], fonts: const []),
    );
    await tester.pump();
    final attachedBuilds = shellBuilds;
    engine.emit(
      UiUpdate(
        kind: 'frame',
        frame: frame(text: 'b'),
        hosts: const [],
        fonts: const [],
      ),
    );
    await tester.pump();
    expect(shellBuilds, attachedBuilds);
    expect(controller.editor.grids[1]!.rows[0]!.single.text, 'b');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.comma, character: '<');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.comma);
    await tester.pump();
    expect(engine.inputs, ['<LT>']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final platform in [TargetPlatform.linux, TargetPlatform.macOS]) {
    testWidgets(
      'routes ${platform.name} clipboard shortcuts without sending keys',
      (tester) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = previous);
        final engine = FakeEngine();
        final native = FakePlatform();
        final controller = NauvimController(engine: engine, platform: native);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          await engine.events.close();
        });
        await tester.pumpWidget(
          WidgetsApp(
            color: const Color(0x00000000),
            builder: (context, _) => NauvimHeadless(
              controller: controller,
              builder: (context, state) => EditorSurface(
                controller: state,
                style: const EditorPaintStyle(),
              ),
            ),
          ),
        );
        engine.emit(
          UiUpdate(
            kind: 'frame',
            frame: frame(text: '界'),
            hosts: const [],
            fonts: const [],
          ),
        );
        await tester.pump();
        await tester.pump();
        final modifiers = platform == TargetPlatform.macOS
            ? [LogicalKeyboardKey.metaLeft]
            : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];
        for (final key in modifiers) {
          await tester.sendKeyDownEvent(key);
        }
        try {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
          await tester.pump();
          expect(engine.pastes, 1);
          expect(native.clipboard, isEmpty);
          controller.editor.beginSelection(const CellPoint(1, 0, 0));
          await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
          await tester.pump();
          expect(native.clipboard, ['界']);
          expect(engine.inputs, isEmpty);

          final extraModifier = platform == TargetPlatform.macOS
              ? LogicalKeyboardKey.shiftLeft
              : LogicalKeyboardKey.metaLeft;
          await tester.sendKeyDownEvent(extraModifier);
          try {
            await tester.sendKeyEvent(LogicalKeyboardKey.keyV, character: 'V');
            controller.editor.beginSelection(const CellPoint(1, 0, 0));
            await tester.sendKeyEvent(LogicalKeyboardKey.keyC, character: 'C');
            await tester.pump();
            expect(engine.pastes, 1);
            expect(native.clipboard, ['界']);
            expect(engine.inputs, [
              platform == TargetPlatform.macOS ? '<D-V>' : '<S-C-D-V>',
              platform == TargetPlatform.macOS ? '<D-C>' : '<S-C-D-C>',
            ]);
          } finally {
            await tester.sendKeyUpEvent(extraModifier);
          }
        } finally {
          for (final key in modifiers.reversed) {
            await tester.sendKeyUpEvent(key);
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('reports viewport movement even within unchanged cell counts', (
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
    Widget region(
      double left, {
      EditorMetricsStyle metrics = const EditorMetricsStyle(),
    }) => Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.only(left: left),
        child: EditorViewportRegion(
          controller: controller,
          metrics: metrics,
          builder: (_, viewport) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpWidget(region(10));
    final before = controller.viewport!;
    await tester.pumpWidget(region(11));
    final after = controller.viewport!;
    expect(after.rows, before.rows);
    expect(after.origin.dx, before.origin.dx + 1);
    expect(after.size, before.size);
    await tester.pumpWidget(
      region(
        11,
        metrics: const EditorMetricsStyle(
          lineHeight: 2,
          cellHeightMultiplier: 1,
        ),
      ),
    );
    expect(identical(controller.viewport!.font, before.font), isTrue);
    expect(controller.viewport!.cellHeight, greaterThan(after.cellHeight));
    expect(controller.viewport!.rows, lessThan(after.rows));
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'repaints fallback colors without changing rows and honors Neovim RGB',
    () async {
      final model = EditorModel()
        ..apply(frame(text: 'M', foreground: null, background: null));
      final renderer = GridRenderer();
      const first = EditorPaintStyle(
        fallbackForeground: Color(0xffff0000),
        fallbackBackground: Color(0xff0000ff),
      );
      const second = EditorPaintStyle(
        fallbackForeground: Color(0xff00ff00),
        fallbackBackground: Color(0xff000000),
      );
      Future<(Set<int>, int)> colors(EditorPaintStyle style) async {
        final recorder = ui.PictureRecorder();
        renderer.paint(
          Canvas(recorder),
          const Size(20, 20),
          model,
          'monospace',
          const [],
          12,
          10,
          20,
          style: style,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(20, 20);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        int rgb(int offset) =>
            (bytes[offset] << 16) |
            (bytes[offset + 1] << 8) |
            bytes[offset + 2];
        final result = (
          {
            for (var offset = 0; offset < bytes.length; offset += 4)
              rgb(offset),
          },
          rgb((10 * 20 + 15) * 4),
        );
        image.dispose();
        picture.dispose();
        return result;
      }

      final row = model.grids[1]!.rows[0];
      final revision = model.grids[1]!.revisions[0];
      final firstColors = await colors(first);
      expect(firstColors.$1, containsAll([0xff0000, 0x0000ff]));
      expect(firstColors.$2, 0x0000ff);
      final secondColors = await colors(second);
      expect(secondColors.$1, containsAll([0x00ff00, 0x000000]));
      expect(secondColors.$1, isNot(contains(0xff0000)));
      expect(secondColors.$1, isNot(contains(0x0000ff)));
      expect(identical(model.grids[1]!.rows[0], row), isTrue);
      expect(model.grids[1]!.revisions[0], revision);
      model.apply(frame(text: 'M', foreground: 0x123456, background: 0x654321));
      final givenRow = model.grids[1]!.rows[0];
      final neovimColors = await colors(first);
      expect(neovimColors.$1, containsAll([0x123456, 0x654321]));
      expect(neovimColors.$2, 0x654321);
      final otherFallback = await colors(second);
      expect(otherFallback.$1, neovimColors.$1);
      expect(otherFallback.$2, neovimColors.$2);
      expect(identical(model.grids[1]!.rows[0], givenRow), isTrue);
      renderer.dispose();
      model.dispose();
    },
  );

  test(
    'changes client selection paint without changing editor state',
    () async {
      final model = EditorModel()..apply(frame(text: ' '));
      model.beginSelection(const CellPoint(1, 0, 0));
      final renderer = GridRenderer();
      final revision = model.grids[1]!.revisions[0];
      Future<List<int>> pixel(Color selection) async {
        final recorder = ui.PictureRecorder();
        renderer.paint(
          Canvas(recorder),
          const Size(10, 20),
          model,
          'monospace',
          const [],
          12,
          10,
          20,
          style: EditorPaintStyle(selectionColor: selection),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(10, 20);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        final result = bytes.sublist((10 * 10 + 5) * 4, (10 * 10 + 5) * 4 + 4);
        image.dispose();
        picture.dispose();
        return result;
      }

      expect(await pixel(const Color(0xffff0000)), [255, 0, 0, 255]);
      expect(await pixel(const Color(0xff0000ff)), [0, 0, 255, 255]);
      expect(model.grids[1]!.revisions[0], revision);
      renderer.dispose();
      model.dispose();
    },
  );
}

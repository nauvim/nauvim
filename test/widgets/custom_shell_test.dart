import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nauvim_flutter/nauvim.dart';
import 'package:nauvim_flutter/nauvim_widgets.dart';

import '../support/fakes.dart';

void main() {
  testWidgets(
    'a non-Material shell drives the same session and grid behavior',
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
        WidgetsApp(
          color: const Color(0xff223344),
          builder: (context, child) => NauvimHeadless(
            controller: controller,
            builder: (context, controller) => controller.attached
                ? EditorSurface(
                    controller: controller,
                    style: const EditorPaintStyle(
                      selectionColor: Color(0xffabcdef),
                    ),
                  )
                : EditorViewportRegion(
                    controller: controller,
                    builder: (context, viewport) => Center(
                      child: GestureDetector(
                        key: const ValueKey('choose-local'),
                        onTap: controller.ready
                            ? controller.connectDefault
                            : null,
                        child: const Text('A different shell'),
                      ),
                    ),
                  ),
          ),
        ),
      );
      engine.emit(const UiUpdate(kind: 'ready', hosts: [], fonts: []));
      await tester.pump();
      await tester.pump();
      expect(engine.starts, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('choose-local')));
      await tester.pump();
      expect(engine.defaults, hasLength(1));
      engine.emit(
        UiUpdate(
          kind: 'frame',
          hosts: const [],
          fonts: const [],
          frame: DisplayFrame(
            full: true,
            grids: const [
              DisplayGrid(
                id: 1,
                width: 3,
                height: 1,
                row: 0,
                col: 0,
                zindex: 0,
                order: 0,
                hidden: false,
              ),
            ],
            rows: const [
              DisplayRow(
                grid: 1,
                row: 0,
                cells: [
                  DisplayCell(text: '界', highlight: 0),
                  DisplayCell(text: '', highlight: 0),
                  DisplayCell(text: 'x', highlight: 0),
                ],
              ),
            ],
            highlights: const [],
            removedGrids: const [],
            foreground: 0xffffff,
            background: 0x123456,
            title: '',
            mode: 'normal',
            busy: false,
            events: const [],
            widgets: const [],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(EditorSurface), findsOneWidget);
      expect(
        controller.editor.grids[1]!.rows[0]!.map((c) => c.text).join(),
        '界x',
      );
      await controller.sendKeys('A!<Esc>');
      expect(engine.inputs, ['A!<Esc>']);
      expect(platform.previews, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:material_ui/material_ui.dart';

import '../../nauvim.dart';
import '../../nauvim_widgets.dart';
import 'theme.dart';

class NauvimToolbar extends StatelessWidget {
  const NauvimToolbar({super.key, required this.controller});
  final NauvimController controller;

  @override
  Widget build(BuildContext context) {
    final appearance = NauvimTheme.of(context);
    return SizedBox(
      height: appearance.toolbarHeight,
      child: Padding(
        padding: appearance.toolbarPadding,
        child: Row(
          children: [
            const Text('Nauvim', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(width: appearance.toolbarGap),
            if (controller.attached)
              Text(
                controller.destination,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.54),
                ),
              ),
            if (controller.attached)
              Expanded(child: NauvimTabBar(controller: controller))
            else
              const Spacer(),
            if (controller.attached)
              NauvimStatus(
                controller: controller,
                maxWidth: MediaQuery.sizeOf(context).width / 4,
              ),
            if (controller.attached)
              IconButton(
                tooltip: 'Detach and keep Neovim running',
                icon: const Icon(Icons.link_off, size: 19),
                onPressed: controller.detach,
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact Neovim indicators that do not consume editor rows.
class NauvimStatus extends StatelessWidget {
  const NauvimStatus({
    super.key,
    required this.controller,
    this.maxWidth = 240,
  });
  final NauvimController controller;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.editor,
    builder: (context, _) {
      final model = controller.editor;
      // Pending command keys are already visible in the active command line.
      if (model.widgets.any((item) => item.kind == 'cmdline')) {
        return const SizedBox.shrink();
      }
      final appearance = NauvimTheme.of(context);
      final paintStyle = EditorPaintStyle(
        fallbackForeground: appearance.editorForeground,
        fallbackBackground: appearance.editorBackground,
      );
      final spans = <InlineSpan>[];
      for (final item in model.widgets.where((item) => item.kind == 'status')) {
        if (!item.chunks.any((chunk) => chunk.text.trim().isNotEmpty)) continue;
        if (spans.isNotEmpty) spans.add(const TextSpan(text: '  '));
        spans.add(
          highlightedChunks(item.chunks, model, paintStyle: paintStyle),
        );
      }
      if (spans.isEmpty) return const SizedBox.shrink();
      final font = controller.font;
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.only(left: appearance.toolbarGap),
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: editorTextStyle(
                font.families,
                font.size,
                variations: font.faces.first.variations,
              ),
              children: spans,
            ),
          ),
        ),
      );
    },
  );
}

class NauvimTabBar extends StatelessWidget {
  const NauvimTabBar({super.key, required this.controller});
  final NauvimController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.editor,
    builder: (context, _) {
      final appearance = NauvimTheme.of(context);
      final tabs = controller.editor.widgets
          .where((widget) => widget.kind == 'tabs')
          .firstOrNull;
      if (tabs == null) return const SizedBox.shrink();
      return ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < tabs.items.length; i++)
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: i == tabs.selected
                    ? appearance.selectedTabColor
                    : null,
              ),
              onPressed: i < tabs.handles.length
                  ? () => controller.selectTab(tabs.handles[i])
                  : null,
              child: Text(tabs.items[i]),
            ),
        ],
      );
    },
  );
}

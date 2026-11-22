import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../nauvim.dart';
import '../../nauvim_widgets.dart';
import 'completion.dart';
import 'theme.dart';

/// The default arrangement of editor grids and Neovim's external widgets.
class NauvimEditor extends StatefulWidget {
  const NauvimEditor({
    super.key,
    required this.controller,
    this.completionItemBuilder,
  });
  final NauvimController controller;
  final NauvimCompletionItemBuilder? completionItemBuilder;

  @override
  State<NauvimEditor> createState() => _NauvimEditorState();
}

class _NauvimEditorState extends State<NauvimEditor> {
  final _commandLineLink = LayerLink();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller.editor,
    builder: (context, _) {
      final controller = widget.controller;
      final appearance = NauvimTheme.of(context);
      final model = controller.editor;
      final paintStyle = EditorPaintStyle(
        fallbackForeground: appearance.editorForeground,
        fallbackBackground: appearance.editorBackground,
        selectionColor: appearance.selectionColor,
        cursorColor: appearance.cursorColor,
        cursorOpacity: appearance.cursorOpacity,
      );
      final font = controller.font;
      final style = editorTextStyle(
        font.families,
        font.size,
        lineHeight: appearance.editorMetrics.lineHeight,
        variations: font.faces.first.variations,
      );
      final activeCommand = model.widgets
          .where((w) => w.kind == 'cmdline')
          .lastOrNull;
      final commandPopup = model.widgets
          .where((w) => w.kind == 'cmdline_popup')
          .firstOrNull;
      final bottomWidgets = model.widgets.where(
        (w) =>
            w.kind != 'popup' &&
            w.kind != 'tabs' &&
            w.kind != 'buffers' &&
            w.kind != 'status' &&
            w.kind != 'cmdline_popup',
      );
      final hasMessages = bottomWidgets.any((item) => item.kind == 'message');
      return EditorViewportRegion(
        controller: controller,
        metrics: appearance.editorMetrics,
        bottomRows: 1,
        builder: (context, viewport) => EditorSurface(
          controller: controller,
          metrics: appearance.editorMetrics,
          viewport: viewport,
          style: paintStyle,
          overlayBuilder: (context, viewport) => [
            for (final popup in model.widgets.where((w) => w.kind == 'popup'))
              _GridCompletion(
                controller: controller,
                viewport: viewport,
                popup: popup,
                style: style,
                itemBuilder: widget.completionItemBuilder,
              ),
          ],
        ),
        overlayBuilder: (context, viewport) {
          final popupWidth = math.min(
            appearance.popupMaxWidth,
            math.max(
              1.0,
              viewport.size.width - appearance.widgetPadding.horizontal,
            ),
          );
          return [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: paintStyle.resolveBackground(model.frame?.background),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: viewport.cellHeight,
                    maxHeight: hasMessages
                        ? viewport.size.height + viewport.cellHeight
                        : viewport.cellHeight,
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Column(
                      children: [
                        for (final item in bottomWidgets)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: appearance.widgetPadding.left,
                                right: appearance.widgetPadding.right,
                              ),
                              child: item.kind == 'cmdline'
                                  ? CommandLine(
                                      item: item,
                                      model: model,
                                      style: style,
                                      active: identical(item, activeCommand),
                                      popupLink: identical(item, activeCommand)
                                          ? _commandLineLink
                                          : null,
                                      popupByteOffset:
                                          identical(item, activeCommand)
                                          ? commandPopup?.col.toInt()
                                          : null,
                                      popupWidth: popupWidth,
                                      cursorColor: appearance.cursorColor,
                                      cursorWidth:
                                          appearance.commandLineCursorWidth,
                                      paintStyle: paintStyle,
                                    )
                                  : RichText(
                                      text: TextSpan(
                                        style: style,
                                        children: [
                                          highlightedChunks(
                                            item.chunks,
                                            model,
                                            paintStyle: paintStyle,
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (activeCommand != null && commandPopup != null)
              Positioned(
                left: 0,
                top: 0,
                child: CompositedTransformFollower(
                  link: _commandLineLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.topLeft,
                  followerAnchor: Alignment.bottomLeft,
                  child: SizedBox(
                    width: popupWidth,
                    child: NauvimCompletionMenu(
                      popup: commandPopup,
                      style: style,
                      onSelected: controller.selectCompletion,
                      itemBuilder: widget.completionItemBuilder,
                    ),
                  ),
                ),
              ),
          ];
        },
      );
    },
  );
}

class _GridCompletion extends StatelessWidget {
  const _GridCompletion({
    required this.controller,
    required this.viewport,
    required this.popup,
    required this.style,
    this.itemBuilder,
  });
  final NauvimController controller;
  final EditorViewport viewport;
  final DisplayWidget popup;
  final TextStyle style;
  final NauvimCompletionItemBuilder? itemBuilder;

  @override
  Widget build(BuildContext context) {
    final grid = controller.editor.grids[popup.grid]?.geometry;
    if (grid == null || grid.hidden) return const SizedBox.shrink();
    final appearance = NauvimTheme.of(context);
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _CompletionLayout(
          anchor: Offset(
            (grid.col + popup.col) * viewport.cellWidth,
            (grid.row + popup.row) * viewport.cellHeight,
          ),
          cellHeight: viewport.cellHeight,
          maxWidth: appearance.popupMaxWidth,
          maxHeight: appearance.popupMaxHeight,
        ),
        child: NauvimCompletionMenu(
          popup: popup,
          style: style,
          onSelected: controller.selectCompletion,
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }
}

// Completion row builders may choose their own heights. Position the menu from
// its measured size so those choices still fit within the editor viewport.
class _CompletionLayout extends SingleChildLayoutDelegate {
  const _CompletionLayout({
    required this.anchor,
    required this.cellHeight,
    required this.maxWidth,
    required this.maxHeight,
  });
  final Offset anchor;
  final double cellHeight;
  final double maxWidth;
  final double maxHeight;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: math.min(maxWidth, constraints.maxWidth),
        maxWidth: math.min(maxWidth, constraints.maxWidth),
        maxHeight: math.min(maxHeight, constraints.maxHeight),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = anchor.dx.clamp(
      0.0,
      math.max(0.0, size.width - childSize.width),
    );
    final below = anchor.dy + cellHeight;
    final top = below + childSize.height <= size.height
        ? below
        : math.max(0.0, anchor.dy - childSize.height);
    return Offset(left.toDouble(), top);
  }

  @override
  bool shouldRelayout(_CompletionLayout oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.cellHeight != cellHeight ||
      oldDelegate.maxWidth != maxWidth ||
      oldDelegate.maxHeight != maxHeight;
}

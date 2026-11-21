/// Unstyled Flutter interaction, layout, and painting primitives for Nauvim.
library;

export 'src/widgets/command_line.dart' show CommandLine;
export 'src/widgets/editor_surface.dart' show EditorSurface;
export 'src/widgets/editor_viewport.dart' show EditorViewportRegion;
export 'src/widgets/grid_renderer.dart' show EditorPainter, GridRenderer;
export 'src/widgets/headless.dart' show NauvimHeadless;
export 'src/widgets/keyboard.dart' show encodeKey, boundKey;
export 'src/widgets/paint_style.dart' show EditorPaintStyle, EditorMetricsStyle;
export 'src/widgets/text.dart'
    show
        byteOffsetToUtf16,
        commandLineOffset,
        decorationStyle,
        editorTextStyle,
        highlightedChunks,
        highlightStyle,
        widgetTextPainter;

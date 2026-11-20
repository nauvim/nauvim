import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

import '../headless/controller.dart';
import '../headless/viewport.dart';
import 'paint_style.dart';

/// Measures a bounded editor region and reports its layout after painting.
///
/// This widget adds no decoration. Its measurements use the controller's current
/// font, and its builder can supply any visual content, including a welcome page.
class EditorViewportRegion extends StatefulWidget {
  const EditorViewportRegion({
    super.key,
    required this.controller,
    required this.builder,
    this.metrics = const EditorMetricsStyle(),
    this.bottomRows = 0,
    this.overlayBuilder,
  });

  final NauvimController controller;
  final Widget Function(BuildContext, EditorViewport) builder;
  final EditorMetricsStyle metrics;
  final int bottomRows;
  final List<Widget> Function(BuildContext, EditorViewport)? overlayBuilder;

  @override
  State<EditorViewportRegion> createState() => _EditorViewportRegionState();
}

class _EditorViewportRegionState extends State<EditorViewportRegion> {
  final _region = GlobalKey();
  late Listenable _layoutChanges;
  EditorFont? _measuredFont;
  (double, double, double)? _measuredMetrics;
  double _cellWidth = 1, _cellHeight = 1;
  double _baseline = 1;
  EditorViewport? _pending;
  WindowGrid? _windowGrid;
  Size? _windowSize;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _listenables();
  }

  @override
  void didUpdateWidget(EditorViewportRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _listenables();
  }

  void _listenables() {
    _layoutChanges = Listenable.merge([
      widget.controller,
      widget.controller.editor,
    ]);
  }

  void _measure(EditorFont font, double scale) {
    final metrics = widget.metrics;
    final stamp = (metrics.lineHeight, metrics.cellHeightMultiplier, scale);
    if (identical(_measuredFont, font) && _measuredMetrics == stamp) return;
    final cells = CellMetrics.fromFont(
      font,
      scale,
      lineHeight: metrics.lineHeight,
      heightMultiplier: metrics.cellHeightMultiplier,
      roundLineMetrics: defaultTargetPlatform == TargetPlatform.macOS,
    );
    _cellWidth = cells.width;
    _cellHeight = cells.height;
    _baseline = cells.baseline;
    _measuredFont = font;
    _measuredMetrics = stamp;
  }

  void _report(EditorViewport? viewport) {
    _pending = viewport;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (_windowGrid case final grid?) {
        widget.controller.updateWindowGrid(
          grid,
          _windowSize!,
          font: _measuredFont,
        );
      }
      final box = _region.currentContext?.findRenderObject();
      final pending = _pending;
      if (box is! RenderBox || !box.hasSize || pending == null) return;
      widget.controller.updateViewport(
        EditorViewport(
          font: pending.font,
          size: box.size,
          origin: box.localToGlobal(Offset.zero),
          cellWidth: pending.cellWidth,
          cellHeight: pending.cellHeight,
          baseline: pending.baseline,
          devicePixelRatio: pending.devicePixelRatio,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _layoutChanges,
    builder: (context, _) {
      final margins = widget.controller.windowMargins;
      final padding = EdgeInsets.fromLTRB(
        margins?.left.toDouble() ?? 0,
        margins?.top.toDouble() ?? 0,
        margins?.right.toDouble() ?? 0,
        margins?.bottom.toDouble() ?? 0,
      );
      return LayoutBuilder(
        builder: (context, outer) {
          final constraints = outer.deflate(padding);
          if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
            throw FlutterError(
              'EditorViewportRegion needs bounded width and height.',
            );
          }
          final font = widget.controller.font;
          final scale = View.of(context).devicePixelRatio;
          _measure(font, scale);
          _windowSize =
              MediaQuery.maybeSizeOf(context) ??
              View.of(context).physicalSize / scale;
          _windowGrid = WindowGrid(
            cellWidth: _cellWidth,
            cellHeight: _cellHeight,
            baseWidth: _windowSize!.width - outer.maxWidth + padding.horizontal,
            baseHeight:
                _windowSize!.height - outer.maxHeight + padding.vertical,
            minRows: widget.bottomRows + 1,
          );
          // Ignore the floating-point noise from converting physical pixels to
          // logical pixels and back; the cell dimensions are physical integers.
          final columns = (constraints.maxWidth / _cellWidth + 1e-7).floor();
          final rows =
              (constraints.maxHeight / _cellHeight + 1e-7).floor() -
              widget.bottomRows;
          if (columns < 1 || rows < 1) {
            _report(null);
            return const SizedBox.shrink();
          }
          final viewport = EditorViewport(
            font: font,
            size: Size(columns * _cellWidth, rows * _cellHeight),
            cellWidth: _cellWidth,
            cellHeight: _cellHeight,
            baseline: _baseline,
            devicePixelRatio: scale,
          );
          _report(viewport);
          return Padding(
            padding: padding,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(
                width: viewport.size.width,
                height: viewport.size.height + widget.bottomRows * _cellHeight,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      width: viewport.size.width,
                      height: viewport.size.height,
                      child: SizedBox(
                        key: _region,
                        child: widget.builder(context, viewport),
                      ),
                    ),
                    ...?widget.overlayBuilder?.call(context, viewport),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

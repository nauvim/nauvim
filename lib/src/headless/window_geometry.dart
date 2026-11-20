import 'protocol.dart';

/// Resolved logical-pixel margins retained for layout and resize hints.
final class WindowMargins {
  const WindowMargins({
    this.top = 0,
    this.bottom = 0,
    this.left = 0,
    this.right = 0,
  });

  final int top, bottom, left, right;
}

/// Startup options after converting geometry to logical pixels.
final class WindowOptions {
  const WindowOptions({
    this.width,
    this.height,
    this.margin = const WindowMargins(),
    this.decorations,
    this.opacity,
    this.startupMode,
  });

  final int? width, height;
  final WindowMargins margin;
  final DisplayDecorations? decorations;
  final double? opacity;
  final DisplayStartupMode? startupMode;

  /// Resolves each axis with its measured cell size, rounding to logical pixels.
  factory WindowOptions.resolve(
    DisplayWindowOptions options, {
    double? cellWidth,
    double? cellHeight,
  }) => WindowOptions(
    width: options.width == null ? null : _pixels(options.width!, cellWidth, 1),
    height: options.height == null
        ? null
        : _pixels(options.height!, cellHeight, 1),
    margin: WindowMargins(
      top: _pixels(options.margin.top, cellHeight, 0),
      bottom: _pixels(options.margin.bottom, cellHeight, 0),
      left: _pixels(options.margin.left, cellWidth, 0),
      right: _pixels(options.margin.right, cellWidth, 0),
    ),
    decorations: options.decorations,
    opacity: options.opacity,
    startupMode: options.startupMode,
  );
}

/// Whether startup geometry needs a viewport measured from the selected font.
bool windowUsesCells(DisplayWindowOptions options) =>
    options.width?.unit == DisplayLengthUnit.em ||
    options.height?.unit == DisplayLengthUnit.em ||
    options.margin.top.unit == DisplayLengthUnit.em ||
    options.margin.bottom.unit == DisplayLengthUnit.em ||
    options.margin.left.unit == DisplayLengthUnit.em ||
    options.margin.right.unit == DisplayLengthUnit.em;

int _pixels(DisplayLength length, double? cell, int minimum) {
  if (!length.value.isFinite || length.value < 0) {
    throw ArgumentError('Window lengths must be finite and nonnegative');
  }
  final double value;
  switch (length.unit) {
    case DisplayLengthUnit.px:
      value = length.value;
    case DisplayLengthUnit.em:
      if (cell == null || !cell.isFinite || cell <= 0) {
        throw ArgumentError(
          'Window geometry needs finite positive cell dimensions',
        );
      }
      value = length.value * cell;
  }
  // Bound before rounding so even finite inputs whose product overflows fit
  // the existing unsigned 32-bit geometry representation.
  return value.clamp(minimum, 0xffffffff).round();
}

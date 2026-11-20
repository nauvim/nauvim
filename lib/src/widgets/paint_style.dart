import 'dart:ui' show Color;

/// Client-owned painting choices layered over Neovim's highlight attributes.
/// Neovim's supplied default colors take precedence over the fallback palette.
final class EditorPaintStyle {
  const EditorPaintStyle({
    this.selectionColor = const Color(0x00000000),
    this.fallbackForeground = const Color(0xffffffff),
    this.fallbackBackground = const Color(0xff000000),
    this.cursorColor,
    this.cursorOpacity = 0.48,
  });

  final Color selectionColor;
  final Color fallbackForeground;
  final Color fallbackBackground;
  final Color? cursorColor;
  final double cursorOpacity;

  Color resolveForeground(int? rgb) =>
      rgb == null ? fallbackForeground : Color(0xff000000 | rgb);

  Color resolveBackground(int? rgb) =>
      rgb == null ? fallbackBackground : Color(0xff000000 | rgb);
}

/// Font line height and cell spacing shared by editor layout and painting.
final class EditorMetricsStyle {
  const EditorMetricsStyle({
    this.lineHeight = 1,
    this.cellHeightMultiplier = 1,
  });

  final double lineHeight;
  final double cellHeightMultiplier;
}

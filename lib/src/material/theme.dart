import 'package:material_ui/material_ui.dart';

import '../../nauvim_widgets.dart' show EditorMetricsStyle;

/// Appearance and spacing of Nauvim's default Material presentation.
@immutable
class NauvimTheme extends ThemeExtension<NauvimTheme> {
  const NauvimTheme({
    this.toolbarHeight = 40,
    this.toolbarPadding = const EdgeInsets.only(left: 18),
    this.toolbarGap = 18,
    this.selectedTabColor = const Color(0xff293345),
    this.welcomeWidth = 420,
    this.welcomePadding = const EdgeInsets.all(24),
    this.errorColor = const Color(0xff49262a),
    this.errorPadding = const EdgeInsets.fromLTRB(16, 8, 4, 8),
    this.errorMaxHeightFraction = 0.25,
    this.widgetPadding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    this.popupColor = const Color(0xff292f3b),
    this.selectedCompletionColor = const Color(0xff425475),
    this.popupMaxWidth = 480,
    this.popupMaxHeight = 280,
    this.popupElevation = 8,
    this.completionPadding = const EdgeInsets.symmetric(
      horizontal: 8,
      vertical: 2,
    ),
    this.editorForeground = const Color(0xffd8dee9),
    this.editorBackground = const Color(0xff15181e),
    this.selectionColor = const Color(0x665b8def),
    this.cursorColor,
    this.cursorOpacity = 0.48,
    this.commandLineCursorWidth = 2,
    this.editorMetrics = const EditorMetricsStyle(),
  });

  final double toolbarHeight;
  final EdgeInsets toolbarPadding;
  final double toolbarGap;
  final Color selectedTabColor;
  final double welcomeWidth;
  final EdgeInsets welcomePadding;
  final Color errorColor;
  final EdgeInsets errorPadding;
  final double errorMaxHeightFraction;
  final EdgeInsets widgetPadding;
  final Color popupColor;
  final Color selectedCompletionColor;
  final double popupMaxWidth;
  final double popupMaxHeight;
  final double popupElevation;
  final EdgeInsets completionPadding;

  /// Fallback used when Neovim leaves its default foreground unset.
  final Color editorForeground;

  /// Fallback used when Neovim leaves its default background unset.
  final Color editorBackground;
  final Color selectionColor;
  final Color? cursorColor;
  final double cursorOpacity;
  final double commandLineCursorWidth;
  final EditorMetricsStyle editorMetrics;

  static NauvimTheme of(BuildContext context) =>
      Theme.of(context).extension<NauvimTheme>() ?? const NauvimTheme();

  @override
  NauvimTheme copyWith({
    double? toolbarHeight,
    EdgeInsets? toolbarPadding,
    double? toolbarGap,
    Color? selectedTabColor,
    double? welcomeWidth,
    EdgeInsets? welcomePadding,
    Color? errorColor,
    EdgeInsets? errorPadding,
    double? errorMaxHeightFraction,
    EdgeInsets? widgetPadding,
    Color? popupColor,
    Color? selectedCompletionColor,
    double? popupMaxWidth,
    double? popupMaxHeight,
    double? popupElevation,
    EdgeInsets? completionPadding,
    Color? editorForeground,
    Color? editorBackground,
    Color? selectionColor,
    Color? cursorColor,
    double? cursorOpacity,
    double? commandLineCursorWidth,
    EditorMetricsStyle? editorMetrics,
  }) => NauvimTheme(
    toolbarHeight: toolbarHeight ?? this.toolbarHeight,
    toolbarPadding: toolbarPadding ?? this.toolbarPadding,
    toolbarGap: toolbarGap ?? this.toolbarGap,
    selectedTabColor: selectedTabColor ?? this.selectedTabColor,
    welcomeWidth: welcomeWidth ?? this.welcomeWidth,
    welcomePadding: welcomePadding ?? this.welcomePadding,
    errorColor: errorColor ?? this.errorColor,
    errorPadding: errorPadding ?? this.errorPadding,
    errorMaxHeightFraction:
        errorMaxHeightFraction ?? this.errorMaxHeightFraction,
    widgetPadding: widgetPadding ?? this.widgetPadding,
    popupColor: popupColor ?? this.popupColor,
    selectedCompletionColor:
        selectedCompletionColor ?? this.selectedCompletionColor,
    popupMaxWidth: popupMaxWidth ?? this.popupMaxWidth,
    popupMaxHeight: popupMaxHeight ?? this.popupMaxHeight,
    popupElevation: popupElevation ?? this.popupElevation,
    completionPadding: completionPadding ?? this.completionPadding,
    editorForeground: editorForeground ?? this.editorForeground,
    editorBackground: editorBackground ?? this.editorBackground,
    selectionColor: selectionColor ?? this.selectionColor,
    cursorColor: cursorColor ?? this.cursorColor,
    cursorOpacity: cursorOpacity ?? this.cursorOpacity,
    commandLineCursorWidth:
        commandLineCursorWidth ?? this.commandLineCursorWidth,
    editorMetrics: editorMetrics ?? this.editorMetrics,
  );

  @override
  NauvimTheme lerp(covariant NauvimTheme? other, double t) {
    if (other == null) return this;
    double mix(double a, double b) => a + (b - a) * t;
    return NauvimTheme(
      toolbarHeight: mix(toolbarHeight, other.toolbarHeight),
      toolbarPadding: EdgeInsets.lerp(toolbarPadding, other.toolbarPadding, t)!,
      toolbarGap: mix(toolbarGap, other.toolbarGap),
      selectedTabColor: Color.lerp(
        selectedTabColor,
        other.selectedTabColor,
        t,
      )!,
      welcomeWidth: mix(welcomeWidth, other.welcomeWidth),
      welcomePadding: EdgeInsets.lerp(welcomePadding, other.welcomePadding, t)!,
      errorColor: Color.lerp(errorColor, other.errorColor, t)!,
      errorPadding: EdgeInsets.lerp(errorPadding, other.errorPadding, t)!,
      errorMaxHeightFraction: mix(
        errorMaxHeightFraction,
        other.errorMaxHeightFraction,
      ),
      widgetPadding: EdgeInsets.lerp(widgetPadding, other.widgetPadding, t)!,
      popupColor: Color.lerp(popupColor, other.popupColor, t)!,
      selectedCompletionColor: Color.lerp(
        selectedCompletionColor,
        other.selectedCompletionColor,
        t,
      )!,
      popupMaxWidth: mix(popupMaxWidth, other.popupMaxWidth),
      popupMaxHeight: mix(popupMaxHeight, other.popupMaxHeight),
      popupElevation: mix(popupElevation, other.popupElevation),
      completionPadding: EdgeInsets.lerp(
        completionPadding,
        other.completionPadding,
        t,
      )!,
      editorForeground: Color.lerp(
        editorForeground,
        other.editorForeground,
        t,
      )!,
      editorBackground: Color.lerp(
        editorBackground,
        other.editorBackground,
        t,
      )!,
      selectionColor: Color.lerp(selectionColor, other.selectionColor, t)!,
      cursorColor: Color.lerp(cursorColor, other.cursorColor, t),
      cursorOpacity: mix(cursorOpacity, other.cursorOpacity),
      commandLineCursorWidth: mix(
        commandLineCursorWidth,
        other.commandLineCursorWidth,
      ),
      editorMetrics: EditorMetricsStyle(
        lineHeight: mix(
          editorMetrics.lineHeight,
          other.editorMetrics.lineHeight,
        ),
        cellHeightMultiplier: mix(
          editorMetrics.cellHeightMultiplier,
          other.editorMetrics.cellHeightMultiplier,
        ),
      ),
    );
  }
}

/// Creates the default Material theme; callers may supply their own ThemeData.
ThemeData defaultNauvimTheme() {
  final theme = ThemeData(
    brightness: Brightness.dark,
    colorSchemeSeed: const Color(0xff8faadc),
    scaffoldBackgroundColor: const Color(0xff15181e),
    useMaterial3: true,
    extensions: const [NauvimTheme()],
  );
  return theme.copyWith(
    textTheme: theme.textTheme.copyWith(
      headlineSmall: theme.textTheme.headlineSmall?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

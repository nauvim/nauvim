import 'package:material_ui/material_ui.dart';

import '../../nauvim.dart';
import '../../nauvim_widgets.dart';
import 'theme.dart';
import 'window.dart';

/// The default Material app; the controller can also drive another widget tree.
class NauvimMaterialApp extends StatelessWidget {
  const NauvimMaterialApp({
    super.key,
    required this.controller,
    this.theme,
    this.windowBuilder,
  });

  final NauvimController controller;
  final ThemeData? theme;
  final NauvimSectionBuilder? windowBuilder;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nauvim',
    debugShowCheckedModeBanner: false,
    theme: theme ?? defaultNauvimTheme(),
    home: NauvimHeadless(
      controller: controller,
      builder: (context, controller) =>
          windowBuilder?.call(context, controller) ??
          NauvimWindow(controller: controller),
    ),
  );
}

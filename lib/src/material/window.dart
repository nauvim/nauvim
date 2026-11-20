import 'package:material_ui/material_ui.dart';

import '../../nauvim.dart';
import '../../nauvim_widgets.dart';
import 'editor.dart';
import 'errors.dart';
import 'toolbar.dart';
import 'theme.dart';
import 'welcome.dart';

typedef NauvimSectionBuilder = Widget Function(
  BuildContext context,
  NauvimController controller,
);

/// Material chrome assembled from replaceable, presentation-only sections.
class NauvimWindow extends StatelessWidget {
  const NauvimWindow({
    super.key,
    required this.controller,
    this.toolbarBuilder,
    this.errorBuilder,
    this.welcomeBuilder,
    this.editorBuilder,
  });

  final NauvimController controller;
  final NauvimSectionBuilder? toolbarBuilder;
  final NauvimSectionBuilder? errorBuilder;
  final NauvimSectionBuilder? welcomeBuilder;
  final NauvimSectionBuilder? editorBuilder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            toolbarBuilder?.call(context, controller) ??
                NauvimToolbar(controller: controller),
            if (controller.errors.isNotEmpty)
              errorBuilder?.call(context, controller) ??
                  NauvimErrorBanner(controller: controller),
            Expanded(
              child: controller.attached
                  ? editorBuilder?.call(context, controller) ??
                        NauvimEditor(controller: controller)
                  : EditorViewportRegion(
                      controller: controller,
                      bottomRows: 1,
                      metrics: NauvimTheme.of(context).editorMetrics,
                      builder: (context, viewport) =>
                          welcomeBuilder?.call(context, controller) ??
                          NauvimWelcome(controller: controller),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

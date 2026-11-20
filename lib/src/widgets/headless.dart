import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

import '../headless/controller.dart';

/// Binds application lifecycle to a controller and builds any client design.
///
/// The caller owns the controller. Editor frames notify `controller.editor`
/// separately, so repainting cells does not rebuild the complete application.
class NauvimHeadless extends StatefulWidget {
  const NauvimHeadless({
    super.key,
    required this.controller,
    required this.builder,
  });

  final NauvimController controller;
  final Widget Function(BuildContext, NauvimController) builder;

  @override
  State<NauvimHeadless> createState() => _NauvimHeadlessState();
}

class _NauvimHeadlessState extends State<NauvimHeadless>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await widget.controller.close();
    return AppExitResponse.exit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.controller.attached) {
      unawaited(widget.controller.focus(state == AppLifecycleState.resumed));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => widget.builder(context, widget.controller),
  );
}

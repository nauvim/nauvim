import 'package:flutter/widgets.dart';

import 'nauvim.dart';
import 'nauvim_desktop.dart';
import 'nauvim_material.dart';
import 'src/bridge/api/application.dart';

/// Compatibility composition for callers supplying a Rust application.
///
/// New frontends can compose a [NauvimController] with [NauvimMaterialApp], or
/// use `NauvimHeadless` with their own widgets.
class NauvimApp extends StatefulWidget {
  const NauvimApp({
    super.key,
    this.application,
    this.startupError,
    this.platform,
  });
  final Application? application;
  final String? startupError;
  final NauvimPlatform? platform;

  @override
  State<NauvimApp> createState() => _NauvimAppState();
}

class _NauvimAppState extends State<NauvimApp> {
  late NauvimController _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    final application = widget.application;
    _controller = NauvimController(
      engine: application == null ? null : RustNauvimEngine(application),
      platform: widget.platform ?? DesktopNauvimPlatform(),
      startupError: widget.startupError,
    );
  }

  @override
  void didUpdateWidget(NauvimApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.application != widget.application ||
        oldWidget.startupError != widget.startupError ||
        oldWidget.platform != widget.platform) {
      _controller.dispose();
      _createController();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NauvimMaterialApp(controller: _controller);
}

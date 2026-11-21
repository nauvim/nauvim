import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../bridge/api/application.dart';
import '../bridge/frb_generated.dart';
import '../headless/controller.dart';
import '../headless/platform.dart';
import '../headless/window_geometry.dart';
import 'engine.dart';
import 'platform.dart';

/// Loads the packaged native library and creates the application controller.
///
/// Startup failures remain available through the controller's error state.
Future<NauvimController> createDesktopController({
  String? configPath,
  NauvimPlatform? platform,
}) async {
  final services = platform ?? DesktopNauvimPlatform();
  final defaults = services is DesktopNauvimPlatform
      ? const WindowOptions()
      : null;
  try {
    final override = Platform.environment['NAUVIM_LIBRARY'];
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final library =
        override ??
        (Platform.isMacOS
            ? '$executableDir/../Frameworks/libnauvim_flutter.dylib'
            : '$executableDir/lib/libnauvim_flutter.so');
    await RustLib.init(externalLibrary: ExternalLibrary.open(library));
    final application = await createApplication(configPath: configPath);
    return NauvimController(
      engine: RustNauvimEngine(application),
      platform: services,
      defaultWindowOptions: defaults,
    );
  } catch (e) {
    return NauvimController(
      platform: services,
      startupError: e.toString(),
      defaultWindowOptions: defaults,
    );
  }
}

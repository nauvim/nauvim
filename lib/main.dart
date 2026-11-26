import 'dart:io';

import 'package:flutter/widgets.dart';

import 'nauvim_desktop.dart';
import 'nauvim_material.dart';
import 'src/desktop/startup_options.dart';

export 'app.dart' show NauvimApp;
export 'window.dart' show NauvimWindow;

const _usage = 'Usage: nauvim [--config PATH] [--lua-path TEMPLATE]...';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final StartupOptions startup;
  try {
    startup = parseStartupOptions(
      arguments,
      luaPathEnvironment: Platform.environment['NAUVIM_LUA_PATH'],
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    await stderr.flush();
    exit(64);
  }
  switch (startup.action) {
    case StartupAction.help:
      stdout.writeln(_usage);
      await stdout.flush();
      exit(0);
    case StartupAction.version:
      stdout.writeln('Nauvim 0.1.0');
      await stdout.flush();
      exit(0);
    case StartupAction.run:
      final controller = await createDesktopController(
        configPath: startup.configPath,
        luaModulePaths: startup.luaModulePaths,
      );
      runApp(NauvimMaterialApp(controller: controller));
  }
}

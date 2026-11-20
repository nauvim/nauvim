import 'dart:io';

import 'package:flutter/widgets.dart';

import 'nauvim_desktop.dart';
import 'nauvim_material.dart';

export 'app.dart' show NauvimApp;
export 'window.dart' show NauvimWindow;

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  String? config;
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--help' || '-h':
        stdout.writeln('Usage: nauvim [--config PATH]');
        await stdout.flush();
        exit(0);
      case '--version':
        stdout.writeln('Nauvim 0.1.0');
        await stdout.flush();
        exit(0);
      case '--config':
        if (i + 1 >= arguments.length || config != null) {
          stderr.writeln('Usage: nauvim [--config PATH]');
          await stderr.flush();
          exit(64);
        }
        config = arguments[++i];
      default:
        stderr.writeln(
          'Unknown option: ${arguments[i]}\nUsage: nauvim [--config PATH]',
        );
        await stderr.flush();
        exit(64);
    }
  }
  final controller = await createDesktopController(configPath: config);
  runApp(NauvimMaterialApp(controller: controller));
}

/// Startup commands understood by Nauvim's desktop executable.
enum StartupAction { run, help, version }

typedef StartupOptions = ({
  StartupAction action,
  String? configPath,
  List<String> luaModulePaths,
});

StartupOptions parseStartupOptions(
  List<String> arguments, {
  String? luaPathEnvironment,
}) {
  String? configPath;
  final luaModulePaths = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--help' || '-h':
        return (
          action: StartupAction.help,
          configPath: null,
          luaModulePaths: const [],
        );
      case '--version':
        return (
          action: StartupAction.version,
          configPath: null,
          luaModulePaths: const [],
        );
      case '--config':
        if (i + 1 >= arguments.length || configPath != null) {
          throw const FormatException('Specify --config PATH once.');
        }
        configPath = arguments[++i];
      case '--lua-path':
        if (i + 1 >= arguments.length || arguments[i + 1].isEmpty) {
          throw const FormatException('Expected a template after --lua-path.');
        }
        luaModulePaths.add(arguments[++i]);
      default:
        throw FormatException('Unknown option: ${arguments[i]}');
    }
  }
  if (luaPathEnvironment != null) {
    luaModulePaths.addAll(
      luaPathEnvironment.split(';').where((template) => template.isNotEmpty),
    );
  }
  return (
    action: StartupAction.run,
    configPath: configPath,
    luaModulePaths: luaModulePaths,
  );
}

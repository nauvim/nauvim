import 'package:flutter_test/flutter_test.dart';
import 'package:nauvim_flutter/src/desktop/startup_options.dart';

void main() {
  test('searches CLI templates before environment templates', () {
    final startup = parseStartupOptions([
      '--lua-path',
      '/cli with space/?.lua',
      '--config',
      '/config/init.lua',
      '--lua-path',
      '/cli/?/init.lua',
    ], luaPathEnvironment: '/env/?.lua;;/env/?/init.lua;');

    expect(startup.action, StartupAction.run);
    expect(startup.configPath, '/config/init.lua');
    expect(startup.luaModulePaths, [
      '/cli with space/?.lua',
      '/cli/?/init.lua',
      '/env/?.lua',
      '/env/?/init.lua',
    ]);
  });

  test('retains defaults when file and module options are absent', () {
    for (final environment in [null, '', ';;']) {
      final startup = parseStartupOptions([], luaPathEnvironment: environment);

      expect(startup.action, StartupAction.run);
      expect(startup.configPath, isNull);
      expect(startup.luaModulePaths, isEmpty);
    }
  });

  test('reports missing arguments and duplicate configuration paths', () {
    for (final arguments in [
      ['--lua-path'],
      ['--lua-path', ''],
      ['--config'],
      ['--config', 'first.lua', '--config', 'second.lua'],
      ['--unknown'],
    ]) {
      expect(() => parseStartupOptions(arguments), throwsFormatException);
    }
  });

  test('recognizes help and version flags', () {
    expect(parseStartupOptions(['--help']).action, StartupAction.help);
    expect(parseStartupOptions(['-h']).action, StartupAction.help);
    expect(parseStartupOptions(['--version']).action, StartupAction.version);
  });
}

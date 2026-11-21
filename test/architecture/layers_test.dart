import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final imports = RegExp(
    r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  List<(File, String)> dependencies(String directory) => [
    for (final file in Directory(
      directory,
    ).listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart'))
        for (final match in imports.allMatches(file.readAsStringSync()))
          (file, match.group(1)!),
  ];

  test(
    'headless behavior has no widget, native service, or visual dependency',
    () {
      final edges = dependencies('lib/src/headless');
      expect(edges, isNotEmpty);
      for (final (file, uri) in edges) {
        final external = Uri.parse(uri);
        if (external.scheme == 'package') {
          expect(uri, 'package:flutter/foundation.dart', reason: file.path);
        } else if (external.scheme == 'dart') {
          expect(
            ['dart:async', 'dart:collection', 'dart:math', 'dart:ui'],
            contains(uri),
            reason: file.path,
          );
        } else if (uri.contains('bridge/')) {
          expect(file.uri.pathSegments.last, 'protocol.dart');
          expect([
            '../bridge/api/display.dart',
            '../bridge/api/keys.dart',
          ], contains(uri));
        } else {
          final resolved = file.absolute.uri.resolve(uri);
          expect(
            resolved.path,
            startsWith('${Directory('lib/src/headless').absolute.path}/'),
            reason: '${file.path}: $uri',
          );
        }
      }
    },
  );

  test(
    'unstyled widgets do not select a skin or call native implementations',
    () {
      final edges = dependencies('lib/src/widgets');
      expect(edges, isNotEmpty);
      for (final (file, uri) in edges) {
        expect(uri, isNot(contains('material')), reason: file.path);
        expect(uri, isNot(contains('desktop')), reason: file.path);
        expect(uri, isNot(contains('bridge')), reason: file.path);
        expect(uri, isNot('dart:io'), reason: file.path);
      }
    },
  );

  test('Material presentation depends on public state and primitives', () {
    final edges = dependencies('lib/src/material');
    expect(edges, isNotEmpty);
    for (final (file, uri) in edges) {
      expect(uri, isNot(contains('desktop')), reason: file.path);
      expect(uri, isNot(contains('bridge')), reason: file.path);
      expect(uri, isNot('dart:io'), reason: file.path);
      if (uri.startsWith('../')) {
        expect(
          ['../../nauvim.dart', '../../nauvim_widgets.dart'],
          contains(uri),
          reason: file.path,
        );
      }
    }
  });

  test('desktop adapters do not depend on the widget tree or Material', () {
    for (final (file, uri) in dependencies('lib/src/desktop')) {
      expect(uri, isNot(contains('material')), reason: file.path);
      expect(uri, isNot(contains('widgets')), reason: file.path);
    }
  });
}

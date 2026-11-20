import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nauvim_flutter/src/desktop/platform.dart';
import 'package:nauvim_flutter/src/headless/protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nauvim/window-options-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('sends native defaults while preserving omitted dimensions', () async {
    await DesktopNauvimPlatform(channel: channel).configureInitialWindow(
      const DisplayWindowOptions(
        margin: DisplayMargins(top: 0, bottom: 0, left: 0, right: 0),
      ),
    );
    expect(calls.single.method, 'configure_window');
    expect(calls.single.arguments, {
      'decorations': 'full',
      'opacity': 1.0,
      'startup_mode': 'windowed',
    });
  });

  test('forwards every startup mode and appearance with dimensions', () async {
    for (final mode in DisplayStartupMode.values) {
      await DesktopNauvimPlatform(channel: channel).configureInitialWindow(
        DisplayWindowOptions(
          width: 960,
          height: 640,
          margin: const DisplayMargins(top: 1, bottom: 2, left: 3, right: 4),
          decorations: DisplayDecorations.none,
          opacity: 0.75,
          startupMode: mode,
        ),
      );
      expect(calls.last.arguments, {
        'width': 960,
        'height': 640,
        'decorations': 'none',
        'opacity': 0.75,
        'startup_mode': mode.name,
      });
    }
  });
}

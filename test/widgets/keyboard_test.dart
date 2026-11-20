import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nauvim_flutter/nauvim_widgets.dart';

Future<String?> chord(
  WidgetTester tester, {
  required LogicalKeyboardKey key,
  PhysicalKeyboardKey physical = PhysicalKeyboardKey.keyT,
  String? character,
  bool control = false,
  bool shift = false,
  bool alt = false,
  bool meta = false,
}) async {
  final modifiers = [
    if (control) LogicalKeyboardKey.controlLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (alt) LogicalKeyboardKey.altLeft,
    if (meta) LogicalKeyboardKey.metaLeft,
  ];
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  try {
    return encodeKey(
      KeyDownEvent(
        physicalKey: physical,
        logicalKey: key,
        character: character,
        timeStamp: Duration.zero,
      ),
    );
  } finally {
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
  }
}

void main() {
  testWidgets('distinguishes Ctrl Shift letters from Ctrl letters', (
    tester,
  ) async {
    expect(
      await chord(
        tester,
        key: LogicalKeyboardKey.keyT,
        character: '\u0014',
        control: true,
      ),
      '<C-T>',
    );
    for (final character in [null, '', '\u0014', 'T', 't']) {
      expect(
        await chord(
          tester,
          key: LogicalKeyboardKey.keyT,
          character: character,
          control: true,
          shift: true,
        ),
        character == 't' ? '<S-C-t>' : '<S-C-T>',
      );
    }
  });

  testWidgets('uses printable shifted punctuation and layout text unchanged', (
    tester,
  ) async {
    expect(
      await chord(
        tester,
        key: LogicalKeyboardKey.digit1,
        physical: PhysicalKeyboardKey.digit1,
        character: '!',
        shift: true,
      ),
      '!',
    );
    expect(
      await chord(
        tester,
        key: LogicalKeyboardKey.digit1,
        physical: PhysicalKeyboardKey.digit1,
        character: '!',
        control: true,
        shift: true,
      ),
      '<C-!>',
    );
    expect(
      await chord(
        tester,
        key: LogicalKeyboardKey.digit1,
        physical: PhysicalKeyboardKey.digit1,
        character: '!',
        alt: true,
        shift: true,
      ),
      '<M-!>',
    );
    expect(
      await chord(
        tester,
        key: LogicalKeyboardKey.keyT,
        character: 'T',
        alt: true,
        shift: true,
      ),
      '<M-T>',
    );
    expect(
      await chord(
        tester,
        key: LogicalKeyboardKey.keyT,
        character: 'T',
        shift: true,
      ),
      'T',
    );
    expect(
      await chord(
        tester,
        key: LogicalKeyboardKey.keyT,
        character: 'Ж',
        control: true,
        shift: true,
      ),
      '<C-Ж>',
    );
    expect(
      await chord(tester, key: LogicalKeyboardKey.keyT, character: 'e\u0301'),
      'e\u0301',
    );
  });

  testWidgets('preserves Shift for special keys and literal escaping', (
    tester,
  ) async {
    expect(
      await chord(
        tester,
        key: LogicalKeyboardKey.arrowLeft,
        physical: PhysicalKeyboardKey.arrowLeft,
        control: true,
        shift: true,
      ),
      '<S-C-Left>',
    );
    expect(
      await chord(
        tester,
        key: LogicalKeyboardKey.comma,
        physical: PhysicalKeyboardKey.comma,
        character: '<',
        shift: true,
      ),
      '<LT>',
    );
    expect(
      await chord(
        tester,
        key: LogicalKeyboardKey.comma,
        physical: PhysicalKeyboardKey.comma,
        character: '<',
        control: true,
        shift: true,
      ),
      '<C-LT>',
    );
  });
}

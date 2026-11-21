import 'package:flutter/services.dart';

import '../headless/key_bindings.dart';
import '../headless/protocol.dart';

/// Resolves one logical key with the exact pressed modifier set.
KeyAction? boundKey(
  NauvimKeyBindings bindings,
  KeyContext context,
  KeyEvent event,
) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  final keyboard = HardwareKeyboard.instance;
  final key = event.logicalKey;
  if (_modifiers.contains(key)) return null;
  final label = key == LogicalKeyboardKey.space
      ? ' '
      : key.keyLabel.replaceAll(' ', '');
  // Flutter supplies uppercase Unicode labels. Canonical ASCII names and
  // letters use lowercase, without losing the remaining Unicode label.
  final name = label.codeUnits.any((c) => c > 127)
      ? label
      : label.toLowerCase();
  final modifiers =
      (keyboard.isControlPressed ? 1 : 0) |
      (keyboard.isShiftPressed ? 2 : 0) |
      (keyboard.isAltPressed ? 4 : 0) |
      (keyboard.isMetaPressed ? 8 : 0);
  return bindings.lookup(context, name, modifiers);
}

final _names = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.escape: 'Esc',
  LogicalKeyboardKey.enter: 'CR',
  LogicalKeyboardKey.numpadEnter: 'CR',
  LogicalKeyboardKey.backspace: 'BS',
  LogicalKeyboardKey.delete: 'Del',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.arrowLeft: 'Left',
  LogicalKeyboardKey.arrowRight: 'Right',
  LogicalKeyboardKey.arrowUp: 'Up',
  LogicalKeyboardKey.arrowDown: 'Down',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.pageUp: 'PageUp',
  LogicalKeyboardKey.pageDown: 'PageDown',
  LogicalKeyboardKey.insert: 'Insert',
  LogicalKeyboardKey.f1: 'F1',
  LogicalKeyboardKey.f2: 'F2',
  LogicalKeyboardKey.f3: 'F3',
  LogicalKeyboardKey.f4: 'F4',
  LogicalKeyboardKey.f5: 'F5',
  LogicalKeyboardKey.f6: 'F6',
  LogicalKeyboardKey.f7: 'F7',
  LogicalKeyboardKey.f8: 'F8',
  LogicalKeyboardKey.f9: 'F9',
  LogicalKeyboardKey.f10: 'F10',
  LogicalKeyboardKey.f11: 'F11',
  LogicalKeyboardKey.f12: 'F12',
  LogicalKeyboardKey.f13: 'F13',
  LogicalKeyboardKey.f14: 'F14',
  LogicalKeyboardKey.f15: 'F15',
  LogicalKeyboardKey.f16: 'F16',
  LogicalKeyboardKey.f17: 'F17',
  LogicalKeyboardKey.f18: 'F18',
  LogicalKeyboardKey.f19: 'F19',
  LogicalKeyboardKey.f20: 'F20',
  LogicalKeyboardKey.f21: 'F21',
  LogicalKeyboardKey.f22: 'F22',
  LogicalKeyboardKey.f23: 'F23',
  LogicalKeyboardKey.f24: 'F24',
};

String? encodeKey(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  final keyboard = HardwareKeyboard.instance;
  final key = event.logicalKey;
  if (_modifiers.contains(key)) return null;
  final name = _names[key];
  final modified =
      keyboard.isControlPressed ||
      keyboard.isAltPressed ||
      keyboard.isMetaPressed;
  var character = event.character;
  if (modified &&
      (character == null ||
          character.isEmpty ||
          character.runes.any((c) => c < 32))) {
    character = key.keyLabel;
  }
  if (name == null && (character == null || character.isEmpty)) return null;
  if (name == null && !modified) return character!.replaceAll('<', '<LT>');
  final buffer = StringBuffer('<');
  // Neovim folds case in Ctrl-letter notation: <C-T> is still <C-t>.
  // Keep Shift explicit there; shifted punctuation already carries its shape.
  if (keyboard.isShiftPressed &&
      (name != null ||
          (keyboard.isControlPressed && _isAsciiLetter(character!)))) {
    buffer.write('S-');
  }
  if (keyboard.isControlPressed) buffer.write('C-');
  if (keyboard.isAltPressed) buffer.write('M-');
  if (keyboard.isMetaPressed) buffer.write('D-');
  final value =
      name ??
      switch (character!) {
        '<' => 'LT',
        ' ' => 'Space',
        '\\' => 'Bslash',
        '|' => 'Bar',
        _ => character,
      };
  buffer.write(value);
  buffer.write('>');
  return buffer.toString();
}

bool _isAsciiLetter(String value) {
  if (value.length != 1) return false;
  final code = value.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
}

final _modifiers = {
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
};

import 'package:flutter/services.dart';

import '../headless/key_bindings.dart';
import '../headless/protocol.dart';

// Configuration objects are immutable. Weak keys let their compiled tables be
// reclaimed when a controller replaces its configuration or is disposed.
final _compiledBindings = Expando<Map<KeyContext, _CompiledBindings>>();

final class _CompiledBindings {
  _CompiledBindings(List<KeyBinding> bindings) {
    for (final binding in bindings) {
      final action = binding.action;
      if (action == null) continue;
      void add(int id) => (keys[id] ??= {})[binding.modifiers] = action;
      final named = _bindingKeys[binding.key];
      if (named != null) {
        add(named.keyId);
        continue;
      }
      if (binding.key.length == 1) {
        final scalar = binding.key.codeUnitAt(0);
        if (scalar < 128) {
          add(LogicalKeyboardKey.unicodePlane | scalar);
          continue;
        }
      }
      // Unicode-plane logical key IDs are the scalar value. Resolve case
      // variants once; key events can then use the supplied ID directly.
      for (final name in [
        binding.key,
        binding.key.toLowerCase(),
        binding.key.toUpperCase(),
      ]) {
        final chars = name.runes.iterator;
        if (!chars.moveNext()) continue;
        final scalar = chars.current;
        if (!chars.moveNext()) add(LogicalKeyboardKey.unicodePlane | scalar);
      }
    }
  }

  final keys = <int, Map<int, KeyAction>>{};

  KeyAction? lookup(int key, int modifiers) => keys[key]?[modifiers];
}

const _bindingKeys = <String, LogicalKeyboardKey>{
  'escape': LogicalKeyboardKey.escape,
  'enter': LogicalKeyboardKey.enter,
  'numpadenter': LogicalKeyboardKey.numpadEnter,
  'backspace': LogicalKeyboardKey.backspace,
  'delete': LogicalKeyboardKey.delete,
  'tab': LogicalKeyboardKey.tab,
  'arrowleft': LogicalKeyboardKey.arrowLeft,
  'arrowright': LogicalKeyboardKey.arrowRight,
  'arrowup': LogicalKeyboardKey.arrowUp,
  'arrowdown': LogicalKeyboardKey.arrowDown,
  'home': LogicalKeyboardKey.home,
  'end': LogicalKeyboardKey.end,
  'pageup': LogicalKeyboardKey.pageUp,
  'pagedown': LogicalKeyboardKey.pageDown,
  'insert': LogicalKeyboardKey.insert,
  'f1': LogicalKeyboardKey.f1,
  'f2': LogicalKeyboardKey.f2,
  'f3': LogicalKeyboardKey.f3,
  'f4': LogicalKeyboardKey.f4,
  'f5': LogicalKeyboardKey.f5,
  'f6': LogicalKeyboardKey.f6,
  'f7': LogicalKeyboardKey.f7,
  'f8': LogicalKeyboardKey.f8,
  'f9': LogicalKeyboardKey.f9,
  'f10': LogicalKeyboardKey.f10,
  'f11': LogicalKeyboardKey.f11,
  'f12': LogicalKeyboardKey.f12,
  'f13': LogicalKeyboardKey.f13,
  'f14': LogicalKeyboardKey.f14,
  'f15': LogicalKeyboardKey.f15,
  'f16': LogicalKeyboardKey.f16,
  'f17': LogicalKeyboardKey.f17,
  'f18': LogicalKeyboardKey.f18,
  'f19': LogicalKeyboardKey.f19,
  'f20': LogicalKeyboardKey.f20,
  'f21': LogicalKeyboardKey.f21,
  'f22': LogicalKeyboardKey.f22,
  'f23': LogicalKeyboardKey.f23,
  'f24': LogicalKeyboardKey.f24,
};

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
  final modifiers =
      (keyboard.isControlPressed ? 1 : 0) |
      (keyboard.isShiftPressed ? 2 : 0) |
      (keyboard.isAltPressed ? 4 : 0) |
      (keyboard.isMetaPressed ? 8 : 0);
  final contexts = _compiledBindings[bindings] ??= {};
  final compiled = contexts[context] ??= _CompiledBindings(
    bindings.bindings(context),
  );
  return compiled.lookup(key.keyId, modifiers);
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

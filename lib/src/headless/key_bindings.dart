import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'protocol.dart';

enum KeyContext { welcome, clipboard, webview }

final _welcomeDefaults = _defaultWelcome();

List<KeyBinding> _defaultWelcome() {
  final bindings = <KeyBinding>[
    const KeyBinding(key: 'j', modifiers: 0, action: KeyAction.selectNext),
    const KeyBinding(
      key: 'arrowdown',
      modifiers: 0,
      action: KeyAction.selectNext,
    ),
    const KeyBinding(key: 'n', modifiers: 1, action: KeyAction.selectNext),
    const KeyBinding(key: 'tab', modifiers: 0, action: KeyAction.selectNext),
    const KeyBinding(key: 'k', modifiers: 0, action: KeyAction.selectPrevious),
    const KeyBinding(
      key: 'arrowup',
      modifiers: 0,
      action: KeyAction.selectPrevious,
    ),
    const KeyBinding(key: 'p', modifiers: 1, action: KeyAction.selectPrevious),
    const KeyBinding(
      key: 'tab',
      modifiers: 2,
      action: KeyAction.selectPrevious,
    ),
    const KeyBinding(key: 'q', modifiers: 0, action: KeyAction.quit),
  ];
  // Preserve the original Enter/Escape behavior with any modifiers. Build the
  // shared defaults once, without temporary maps for each modifier set.
  for (var modifiers = 0; modifiers < 16; modifiers++) {
    bindings.add(
      KeyBinding(
        key: 'enter',
        modifiers: modifiers,
        action: KeyAction.activate,
      ),
    );
    bindings.add(
      KeyBinding(
        key: 'numpadenter',
        modifiers: modifiers,
        action: KeyAction.activate,
      ),
    );
    bindings.add(
      KeyBinding(key: 'escape', modifiers: modifiers, action: KeyAction.back),
    );
  }
  return UnmodifiableListView(bindings);
}

List<KeyBinding> _merge(
  List<KeyBinding> defaults,
  List<KeyBinding>? overrides,
) {
  if (overrides == null || overrides.isEmpty) return defaults;
  return UnmodifiableListView([
    ...overrides,
    for (final binding in defaults)
      if (!overrides.any(
        (override) =>
            override.key == binding.key &&
            override.modifiers == binding.modifiers,
      ))
        binding,
  ]);
}

/// Effective logical-key bindings, including defaults and explicit removals.
final class NauvimKeyBindings {
  NauvimKeyBindings([KeyBindings? overrides])
    : _welcome = _merge(_welcomeDefaults, overrides?.welcome),
      _clipboard = _merge(
        defaultTargetPlatform == TargetPlatform.macOS
            ? const [
                KeyBinding(key: 'c', modifiers: 8, action: KeyAction.copy),
                KeyBinding(key: 'v', modifiers: 8, action: KeyAction.paste),
              ]
            : const [
                KeyBinding(key: 'c', modifiers: 3, action: KeyAction.copy),
                KeyBinding(key: 'v', modifiers: 3, action: KeyAction.paste),
              ],
        overrides?.clipboard,
      ),
      _webview = _merge(const [
        KeyBinding(key: 'r', modifiers: 1, action: KeyAction.reload),
        KeyBinding(key: 'w', modifiers: 1, action: KeyAction.close),
        KeyBinding(key: 'escape', modifiers: 0, action: KeyAction.focusEditor),
      ], overrides?.webview);

  final List<KeyBinding> _welcome, _clipboard, _webview;

  KeyAction? lookup(KeyContext context, String key, int modifiers) {
    for (final binding in bindings(context)) {
      if (binding.key == key && binding.modifiers == modifiers) {
        return binding.action;
      }
    }
    return null;
  }

  List<KeyBinding> bindings(KeyContext context) => switch (context) {
    KeyContext.welcome => _welcome,
    KeyContext.clipboard => _clipboard,
    KeyContext.webview => _webview,
  };

  String hint(KeyContext context, KeyAction action) {
    final buffer = StringBuffer();
    final limit = action == KeyAction.back || action == KeyAction.quit ? 1 : 2;
    var count = 0;
    for (final binding in bindings(context)) {
      if (binding.action != action) continue;
      if (count != 0) buffer.write('/');
      final modifiers = binding.modifiers;
      final key = switch (binding.key) {
        'arrowup' => '↑',
        'arrowdown' => '↓',
        'arrowleft' => '←',
        'arrowright' => '→',
        'escape' => 'Esc',
        'enter' => 'Enter',
        'numpadenter' => 'NumpadEnter',
        'tab' => 'Tab',
        ' ' => 'Space',
        '+' => 'Plus',
        '-' => 'Minus',
        '_' => 'Underscore',
        final key => key.toLowerCase(),
      };
      if (modifiers & 1 != 0) buffer.write('Ctrl-');
      if (modifiers & 2 != 0) buffer.write('Shift-');
      if (modifiers & 4 != 0) buffer.write('Alt-');
      if (modifiers & 8 != 0) buffer.write('Super-');
      buffer.write(key);
      if (++count == limit) break;
    }
    return count == 0 ? 'unbound' : buffer.toString();
  }
}

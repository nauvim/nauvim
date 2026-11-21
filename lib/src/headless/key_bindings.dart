import 'package:flutter/foundation.dart';

import 'protocol.dart';

enum KeyContext { welcome, clipboard, webview }

/// Effective logical-key bindings, including defaults and explicit removals.
final class NauvimKeyBindings {
  NauvimKeyBindings([KeyBindings? overrides]) {
    final clipboardModifiers = defaultTargetPlatform == TargetPlatform.macOS
        ? 8
        : 3;
    final welcome = <(String, int), KeyAction?>{
      ('j', 0): KeyAction.selectNext,
      ('arrowdown', 0): KeyAction.selectNext,
      ('n', 1): KeyAction.selectNext,
      ('tab', 0): KeyAction.selectNext,
      ('k', 0): KeyAction.selectPrevious,
      ('arrowup', 0): KeyAction.selectPrevious,
      ('p', 1): KeyAction.selectPrevious,
      ('tab', 2): KeyAction.selectPrevious,
      ('enter', 0): KeyAction.activate,
      ('numpadenter', 0): KeyAction.activate,
      ('escape', 0): KeyAction.back,
      ('q', 0): KeyAction.quit,
      // The original welcome handler accepted Enter and Escape with any
      // modifiers. Keep each variant as an explicit, independently overridable
      // chord while matching all configured shortcuts exactly.
      for (var modifiers = 1; modifiers < 16; modifiers++) ...{
        ('enter', modifiers): KeyAction.activate,
        ('numpadenter', modifiers): KeyAction.activate,
        ('escape', modifiers): KeyAction.back,
      },
    };
    final clipboard = <(String, int), KeyAction?>{
      ('c', clipboardModifiers): KeyAction.copy,
      ('v', clipboardModifiers): KeyAction.paste,
    };
    Map<(String, int), KeyAction?> merge(
      Map<(String, int), KeyAction?> defaults,
      List<KeyBinding> overrides,
    ) => Map.unmodifiable({
      for (final binding in overrides)
        (binding.key, binding.modifiers): binding.action,
      for (final entry in defaults.entries)
        if (!overrides.any(
          (binding) => (binding.key, binding.modifiers) == entry.key,
        ))
          entry.key: entry.value,
    });

    _contexts = {
      KeyContext.welcome: merge(welcome, overrides?.welcome ?? const []),
      KeyContext.clipboard: merge(clipboard, overrides?.clipboard ?? const []),
      KeyContext.webview: merge({}, overrides?.webview ?? const []),
    };
  }

  late final Map<KeyContext, Map<(String, int), KeyAction?>> _contexts;

  KeyAction? lookup(KeyContext context, String key, int modifiers) =>
      _contexts[context]?[(key, modifiers)];

  Iterable<KeyBinding> bindings(KeyContext context) sync* {
    for (final entry in _contexts[context]!.entries) {
      yield KeyBinding(
        key: entry.key.$1,
        modifiers: entry.key.$2,
        action: entry.value,
      );
    }
  }

  String hint(KeyContext context, KeyAction action) {
    final keys = bindings(context)
        .where((binding) => binding.action == action)
        .take(action == KeyAction.back || action == KeyAction.quit ? 1 : 2)
        .map((binding) {
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
            final key => key,
          };
          return '${modifiers & 1 != 0 ? 'Ctrl+' : ''}'
              '${modifiers & 2 != 0 ? 'Shift+' : ''}'
              '${modifiers & 4 != 0 ? 'Alt+' : ''}'
              '${modifiers & 8 != 0 ? 'Super+' : ''}$key';
        });
    return keys.isEmpty ? 'unbound' : keys.join('/');
  }
}

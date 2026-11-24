import 'dart:async';

import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../nauvim.dart';
import '../../nauvim_widgets.dart' show boundKey;
import 'theme.dart';

class NauvimWelcome extends StatefulWidget {
  const NauvimWelcome({super.key, required this.controller});
  final NauvimController controller;

  @override
  State<NauvimWelcome> createState() => _NauvimWelcomeState();
}

class _NauvimWelcomeState extends State<NauvimWelcome> {
  final _host = TextEditingController();
  final _hostFocus = FocusNode();
  final _pageFocus = FocusNode(skipTraversal: true);
  final _itemKeys = <GlobalKey>[];
  int _selected = 0;
  bool _typing = false;
  late bool _connecting;
  late String _destination;

  int get _manualIndex => widget.controller.hosts.length + 1;
  int get _selectedIndex => _selected.clamp(0, _manualIndex);
  bool get _available =>
      widget.controller.ready &&
      widget.controller.hasEngine &&
      !widget.controller.connecting &&
      !widget.controller.closing;

  @override
  void initState() {
    super.initState();
    _restoreDestination();
    widget.controller.addListener(_syncConnection);
    _focusMenu();
  }

  void _restoreDestination({bool keepDraft = false}) {
    _connecting = widget.controller.connecting;
    _typing = false;
    final destination = widget.controller.destination;
    _destination = destination;
    final host = widget.controller.hosts.indexOf(destination);
    _selected = destination.isEmpty
        ? 0
        : host < 0
        ? _manualIndex
        : host + 1;
    if (!keepDraft || (host < 0 && destination.isNotEmpty)) {
      _host.text = host < 0 ? destination : '';
    }
  }

  @override
  void didUpdateWidget(NauvimWelcome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncConnection);
      _restoreDestination();
      widget.controller.addListener(_syncConnection);
      _focusMenu();
    }
  }

  void _syncConnection() {
    final connecting = widget.controller.connecting;
    final destination = widget.controller.destination;
    if (destination != _destination) {
      setState(() => _restoreDestination(keepDraft: true));
      _focusMenu();
      return;
    }
    if (connecting == _connecting) return;
    setState(() {
      _connecting = connecting;
      _typing = false;
    });
    _focusMenu();
  }

  void _focusMenu() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.controller.closing) return;
      _pageFocus.requestFocus();
      _showSelection();
    });
  }

  void _showSelection() {
    final index = _selectedIndex;
    if (index >= _itemKeys.length) return;
    final context = _itemKeys[index].currentContext;
    if (context == null) return;
    final item = context.findRenderObject();
    final viewport = RenderAbstractViewport.maybeOf(item);
    if (item is! RenderBox || viewport is! RenderBox) return;
    final above = item.localToGlobal(Offset.zero, ancestor: viewport).dy < 0;
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: above
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ),
    );
  }

  void _move(int delta) {
    setState(() => _selected = (_selectedIndex + delta) % (_manualIndex + 1));
    _focusMenu();
  }

  void _editHost() {
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_typing || !_available) return;
      _hostFocus.requestFocus();
      final context = _hostFocus.context;
      if (context != null) unawaited(Scrollable.ensureVisible(context));
    });
  }

  void _back() {
    setState(() => _typing = false);
    _focusMenu();
  }

  void _activate(int index) {
    if (!_available) return;
    setState(() => _selected = index);
    if (index == _manualIndex) {
      _editHost();
    } else {
      unawaited(
        index == 0
            ? widget.controller.connectDefault()
            : widget.controller.connect(widget.controller.hosts[index - 1]),
      );
    }
  }

  void _connectHost() {
    if (_available && _host.text.trim().isNotEmpty) {
      unawaited(widget.controller.connect(_host.text));
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final action = boundKey(
      widget.controller.keyBindings,
      KeyContext.welcome,
      event,
    );
    if (!_typing && action == KeyAction.quit) {
      if (event is KeyDownEvent) unawaited(widget.controller.close());
      return KeyEventResult.handled;
    }
    if (action == KeyAction.back) {
      if (widget.controller.connecting) {
        if (event is KeyDownEvent) unawaited(widget.controller.detach());
        return KeyEventResult.handled;
      }
      if (_typing) {
        _back();
        return KeyEventResult.handled;
      }
    }
    if (_typing) {
      if (action == KeyAction.activate) {
        if (event is KeyDownEvent) _connectHost();
        return KeyEventResult.handled;
      }
      // Single-line text input must not submit through an unbound Enter.
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (!_available) return KeyEventResult.ignored;
    if (action == KeyAction.activate) {
      if (event is KeyDownEvent) _activate(_selectedIndex);
      return KeyEventResult.handled;
    }
    final delta = switch (action) {
      KeyAction.selectNext => 1,
      KeyAction.selectPrevious => -1,
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;
    _move(delta);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncConnection);
    _host.dispose();
    _hostFocus.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final appearance = NauvimTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final count = _manualIndex + 1;
    while (_itemKeys.length < count) {
      _itemKeys.add(GlobalKey());
    }
    if (_itemKeys.length > count) {
      _itemKeys.removeRange(count, _itemKeys.length);
    }
    return Focus(
      focusNode: _pageFocus,
      autofocus: true,
      onKeyEvent: _key,
      child: Center(
        child: SingleChildScrollView(
          padding: appearance.welcomePadding,
          child: SizedBox(
            width: appearance.welcomeWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your Neovim, anywhere.', style: textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(
                  'Choose a destination to start or resume a session.',
                  style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 24),
                ExcludeFocus(
                  child: Column(
                    children: [
                      for (var i = 0; i < count; i++)
                        ListTile(
                          key: _itemKeys[i],
                          selected: i == _selectedIndex,
                          selectedTileColor: appearance.selectedTabColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          leading: Icon(
                            i == 0
                                ? Icons.home
                                : i == _manualIndex
                                ? Icons.edit
                                : Icons.dns,
                          ),
                          title: Text(
                            i == 0
                                ? 'Default host'
                                : i == _manualIndex
                                ? 'Type yourself'
                                : controller.hosts[i - 1],
                          ),
                          subtitle:
                              i == _manualIndex &&
                                  !_typing &&
                                  _host.text.isNotEmpty
                              ? Text(
                                  _host.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          trailing: i == _selectedIndex
                              ? const Icon(Icons.chevron_right)
                              : null,
                          onTap: _available ? () => _activate(i) : null,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_typing) ...[
                  TextField(
                    controller: _host,
                    focusNode: _hostFocus,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Host alias',
                      border: OutlineInputBorder(),
                    ),
                    onEditingComplete: () {},
                    onSubmitted: (_) {
                      if (controller.keyBindings.lookup(
                            KeyContext.welcome,
                            'enter',
                            0,
                          ) ==
                          KeyAction.activate) {
                        _connectHost();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _available ? _connectHost : null,
                        icon: const Icon(Icons.terminal),
                        label: const Text('Connect to alias'),
                      ),
                      TextButton(onPressed: _back, child: const Text('Back')),
                    ],
                  ),
                ],
                if (controller.connecting)
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Connecting to ${controller.destination.isEmpty ? 'the default host' : controller.destination}…',
                      ),
                      TextButton(
                        onPressed: controller.detach,
                        child: const Text('Cancel connection'),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Text(
                  _typing
                      ? '${controller.keyBindings.hint(KeyContext.welcome, KeyAction.activate)}: connect · ${controller.keyBindings.hint(KeyContext.welcome, KeyAction.back)}: back to destinations'
                      : '${controller.keyBindings.hint(KeyContext.welcome, KeyAction.selectNext)}: next · ${controller.keyBindings.hint(KeyContext.welcome, KeyAction.selectPrevious)}: previous · ${controller.keyBindings.hint(KeyContext.welcome, KeyAction.activate)}: select · ${controller.keyBindings.hint(KeyContext.welcome, KeyAction.quit)}: quit · ${controller.keyBindings.hint(KeyContext.welcome, KeyAction.back)}: cancel',
                  style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 20),
                Text(
                  'Closing Nauvim leaves your editor running.\nSelect the same host to resume.',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.38),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

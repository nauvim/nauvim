import 'dart:async';

import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../nauvim.dart';
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

  void _restoreDestination() {
    _connecting = widget.controller.connecting;
    _typing = false;
    final destination = widget.controller.destination;
    final host = widget.controller.hosts.indexOf(destination);
    _selected = destination.isEmpty
        ? 0
        : host < 0
        ? _manualIndex
        : host + 1;
    _host.text = host < 0 ? destination : '';
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
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final plain =
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isShiftPressed;
    if (!_typing && key == LogicalKeyboardKey.keyQ && plain) {
      if (event is KeyDownEvent) unawaited(widget.controller.close());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (widget.controller.connecting) {
        if (event is KeyDownEvent) unawaited(widget.controller.detach());
        return KeyEventResult.handled;
      }
      if (_typing) {
        _back();
        return KeyEventResult.handled;
      }
    }
    final enter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (_typing) return KeyEventResult.ignored;
    if (!_available) return KeyEventResult.ignored;
    if (enter) {
      if (event is KeyDownEvent) _activate(_selectedIndex);
      return KeyEventResult.handled;
    }
    final control =
        keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isShiftPressed;
    int? delta;
    if (plain) {
      if (key == LogicalKeyboardKey.keyJ ||
          key == LogicalKeyboardKey.arrowDown) {
        delta = 1;
      } else if (key == LogicalKeyboardKey.keyK ||
          key == LogicalKeyboardKey.arrowUp) {
        delta = -1;
      }
    }
    if (control &&
        (key == LogicalKeyboardKey.keyN || key == LogicalKeyboardKey.keyP)) {
      delta = key == LogicalKeyboardKey.keyN ? 1 : -1;
    }
    if (key == LogicalKeyboardKey.tab &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      delta = keyboard.isShiftPressed ? -1 : 1;
    }
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
                                ? Icons.computer
                                : i == _manualIndex
                                ? Icons.edit
                                : Icons.dns,
                          ),
                          title: Text(
                            i == 0
                                ? 'Default local host'
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
                    onSubmitted: (_) => _connectHost(),
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
                        'Connecting to ${controller.destination.isEmpty ? 'the default local host' : controller.destination}…',
                      ),
                      TextButton(
                        onPressed: controller.detach,
                        child: const Text('Cancel connection'),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Text(
                  _typing ? 'Enter: connect · Esc: back to destinations' : 'j/k or ↑/↓: move · Enter: select · q: quit · Esc: cancel',
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

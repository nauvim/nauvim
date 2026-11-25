import 'package:flutter/services.dart';

typedef EditorPreedit = ({String text, TextSelection selection});

/// Adapts Flutter's native text input to an editor that consumes committed keys.
final class EditorTextInput with TextInputClient {
  EditorTextInput({
    required this.onPreedit,
    required this.onCommit,
    required this.onClosed,
  });

  final ValueChanged<EditorPreedit?> onPreedit;
  final ValueChanged<String> onCommit;
  final VoidCallback onClosed;

  TextInputConnection? _connection;
  TextEditingValue _value = const TextEditingValue(
    selection: TextSelection.collapsed(offset: 0),
  );
  String _committed = '';

  bool get attached => _connection?.attached ?? false;

  void open(int viewId) {
    _connection = TextInput.attach(
      this,
      TextInputConfiguration(
        viewId: viewId,
        inputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
      ),
    )..setEditingState(_value);
    _connection?.show();
  }

  void close() {
    final connection = _connection;
    _connection = null;
    connection?.close();
  }

  void updateGeometry(Size size, Rect caret, Rect composing) {
    final connection = _connection;
    if (connection == null || !connection.attached) return;

    connection
      ..setEditableSizeAndTransform(size, Matrix4.identity())
      ..setCaretRect(caret)
      ..setComposingRect(composing);
  }

  @override
  TextEditingValue get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    final connection = _connection;
    if (connection == null || !connection.attached) return;

    final composing =
        value.isComposingRangeValid && !value.composing.isCollapsed
        ? value.composing
        : null;
    final committedEnd = composing?.start ?? value.text.length;
    // Keep the native buffer for the lifetime of this connection. Resetting it
    // after a commit could overwrite edits that are already on their way to Dart.
    // The editor can insert new text, so only accept edits to the pending suffix.
    if (committedEnd < _committed.length ||
        !value.text.startsWith(_committed) ||
        (composing != null && composing.end != value.text.length)) {
      connection.setEditingState(_value);
      return;
    }

    final committed = value.text.substring(_committed.length, committedEnd);
    _committed = value.text.substring(0, committedEnd);
    _value = value;

    if (composing == null) {
      onPreedit(null);
    } else {
      final text = composing.textInside(value.text);
      int offset(int n) => (n - composing.start).clamp(0, text.length);
      final selection = value.selection.isValid
          ? TextSelection(
              baseOffset: offset(value.selection.baseOffset),
              extentOffset: offset(value.selection.extentOffset),
              affinity: value.selection.affinity,
              isDirectional: value.selection.isDirectional,
            )
          : TextSelection.collapsed(offset: text.length);
      onPreedit((text: text, selection: selection));
    }
    if (committed.isNotEmpty) onCommit(committed);
  }

  @override
  void connectionClosed() {
    _connection?.connectionClosedReceived();
    _connection = null;
    onClosed();
  }

  @override
  void performAction(TextInputAction action) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
}

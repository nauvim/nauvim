import 'dart:ui' show Rect;

/// Editing updates from the client's native text input system.
sealed class EditorTextInputEvent {
  const EditorTextInputEvent();
}

typedef EditorPreeditSegment = ({int start, int end, bool selected});

/// Provisional text and its UTF-16 selection and segment ranges.
final class EditorPreedit extends EditorTextInputEvent {
  const EditorPreedit({
    required this.text,
    required this.selectionStart,
    required this.selectionEnd,
    this.segments = const [],
  });

  final String text;
  final int selectionStart, selectionEnd;
  final List<EditorPreeditSegment> segments;
}

final class EditorTextCommit extends EditorTextInputEvent {
  const EditorTextCommit(this.text);

  final String text;
}

/// Native editor text input available from desktop platforms that provide it.
abstract interface class EditorTextInputPlatform {
  Future<void> openTextInput(
    int client,
    void Function(EditorTextInputEvent) onEdit,
  );
  Future<void> closeTextInput(int client);
  Future<void> updateTextInputGeometry(
    int client, {
    required Rect caret,
    required Rect composing,
  });
}

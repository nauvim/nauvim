import 'protocol.dart';

/// The session operations used by the headless application controller.
abstract interface class NauvimEngine {
  /// Supplies ordered updates to the controller's single subscription.
  Stream<UiUpdate> updates();

  /// Applies startup selection once the editor has a measured cell size.
  Future<void> start({required int width, required int height});
  Future<void> connect({
    required String host,
    required int width,
    required int height,
  });
  Future<void> connectDefault({required int width, required int height});
  Future<void> detach();
  Future<void> input({required String keys});
  Future<void> paste();
  Future<void> resize({required int width, required int height});
  Future<void> focus({required bool focused});
  Future<void> selectPopupmenuItem({required int index});
  Future<void> setCurrentTabpage({required int tabpage});
  Future<void> setCurrentBuffer({required int buffer});

  /// Finishes engine cleanup, preserving host Neovim processes.
  ///
  /// Final diagnostics must precede a `shutdown` update or stream termination.
  /// The controller drains that stream separately before closing its window.
  Future<void> close();
}

/// Delivers editor input using the attachment that supplied the displayed frame.
abstract interface class AttachmentInputEngine {
  Future<void> inputOnAttachment({
    required String keys,
    required InputAttachment attachment,
  });
}

/// Receives actual client-area dimensions in logical pixels for persistence.
abstract interface class WindowSizeRecorder {
  void recordWindowSize({required int width, required int height});
}

import '../bridge/api/application.dart';
import '../headless/engine.dart';
import '../headless/protocol.dart';

/// Forwards session operations to the opaque Rust application.
final class RustNauvimEngine
    implements NauvimEngine, AttachmentInputEngine, WindowSizeRecorder {
  const RustNauvimEngine(this.application);
  final Application application;

  @override
  Stream<UiUpdate> updates() => application.updates();
  @override
  Future<void> start({required int width, required int height}) =>
      application.start(width: width, height: height);
  @override
  Future<void> connect({
    required String host,
    required int width,
    required int height,
  }) => application.connect(host: host, width: width, height: height);
  @override
  Future<void> connectDefault({required int width, required int height}) =>
      application.connectDefault(width: width, height: height);
  @override
  Future<void> detach() => application.detach();
  @override
  Future<void> input({required String keys}) => application.input(keys: keys);
  @override
  Future<void> inputOnAttachment({
    required String keys,
    required InputAttachment attachment,
  }) => application.inputOnAttachment(keys: keys, attachment: attachment);
  @override
  Future<void> paste() => application.paste();
  @override
  Future<void> resize({required int width, required int height}) =>
      application.resize(width: width, height: height);
  @override
  void recordWindowSize({required int width, required int height}) =>
      application.recordWindowSize(width: width, height: height);
  @override
  Future<void> focus({required bool focused}) =>
      application.focus(focused: focused);
  @override
  Future<void> selectPopupmenuItem({required int index}) =>
      application.selectPopupmenuItem(index: index);
  @override
  Future<void> setCurrentTabpage({required int tabpage}) =>
      application.setCurrentTabpage(tabpage: tabpage);
  @override
  Future<void> setCurrentBuffer({required int buffer}) =>
      application.setCurrentBuffer(buffer: buffer);
  @override
  Future<void> close() => application.close();
}

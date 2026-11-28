import Cocoa
import FlutterMacOS

final class EditorFlutterViewController: FlutterViewController {
  private var textInputChannel: FlutterMethodChannel?
  private var requestedClient: Int?
  private var editorHasFocus = false
  private var geometry: TextInputGeometry?
  private var textInput: EditorTextInput?
  private weak var previousResponder: NSResponder?
  private let keyEquivalents = NSHashTable<NSEvent>(options: [.weakMemory, .objectPointerPersonality])
  private var consumedKeyDowns: Set<UInt16> = []

  func installNativeTextInput() {
    let channel = FlutterMethodChannel(
      name: "nauvim/native_text_input", binaryMessenger: engine.binaryMessenger)
    textInputChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      let args = call.arguments as? [String: Any] ?? [:]
      let client = args["client"] as? Int

      switch call.method {
      case "open":
        if let client, requestedClient != client {
          requestedClient = nil
          endTextInput()
          requestedClient = client
          geometry = nil
          startTextInput()
        }
      case "close":
        if let client, requestedClient == client {
          requestedClient = nil
          geometry = nil
          endTextInput()
        }
      case "geometry":
        if let client, requestedClient == client {
          let newGeometry = TextInputGeometry(args)
          if geometry != newGeometry {
            geometry = newGeometry
            textInput?.geometry = newGeometry
          }
        }
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    }
  }

  func setNativeTextInputFocus(_ hasFocus: Bool) {
    editorHasFocus = hasFocus
    if !hasFocus || (textInput != nil && view.window?.firstResponder !== textInput) {
      endTextInput()
    }
    if hasFocus { startTextInput() }
  }

  func invalidateNativeTextInputCoordinates() {
    textInput?.invalidateCoordinates()
  }

  override func keyDown(with event: NSEvent) {
    dispatchKeyDown(event, isKeyEquivalent: false)
  }

  private func dispatchKeyDown(_ event: NSEvent, isKeyEquivalent: Bool) {
    if textInput?.handle(event, isKeyEquivalent: isKeyEquivalent) == true {
      if !event.isARepeat {
        consumedKeyDowns.insert(event.keyCode)
      }
      return
    }

    consumedKeyDowns.remove(event.keyCode)
    super.keyDown(with: event)
  }

  override func keyUp(with event: NSEvent) {
    // Keep Flutter's key state paired for presses it received.
    if consumedKeyDowns.remove(event.keyCode) == nil {
      super.keyUp(with: event)
    }
  }

  override func flagsChanged(with event: NSEvent) {
    if textInput?.handleModifierPress(event) != true {
      super.flagsChanged(with: event)
    }
  }

  fileprivate func dispatchKeyEquivalent(_ event: NSEvent) -> Bool {
    // Flutter can send an unhandled event back through AppKit to reach menus.
    guard !keyEquivalents.contains(event) else { return false }
    keyEquivalents.add(event)
    dispatchKeyDown(event, isKeyEquivalent: true)
    return true
  }

  private func startTextInput() {
    guard textInput == nil, editorHasFocus, let client = requestedClient,
          let channel = textInputChannel, let window = view.window else {
      return
    }
    let session = EditorTextInput(client: client, controller: self, channel: channel)
    session.geometry = geometry
    previousResponder = window.firstResponder
    textInput = session
    view.addSubview(session)
    if window.makeFirstResponder(session) {
      session.watchCommandReleases()
      session.invalidateCoordinates()
    } else {
      endTextInput()
    }
  }

  private func endTextInput() {
    guard let session = textInput else { return }
    textInput = nil
    session.discardComposition()
    session.stopWatchingCommandReleases()
    if let window = session.window, window.firstResponder === session {
      window.makeFirstResponder(previousResponder ?? view)
    }
    session.removeFromSuperview()
    previousResponder = nil
  }
}

private struct TextInputGeometry: Equatable {
  let caret: NSRect
  let composing: NSRect

  init?(_ args: [String: Any]) {
    func rect(_ value: Any?) -> NSRect? {
      guard let dict = value as? [String: Any],
            let x = (dict["left"] as? NSNumber)?.doubleValue, x.isFinite,
            let y = (dict["top"] as? NSNumber)?.doubleValue, y.isFinite,
            let width = (dict["width"] as? NSNumber)?.doubleValue, width.isFinite, width >= 0,
            let height = (dict["height"] as? NSNumber)?.doubleValue, height.isFinite, height > 0
      else { return nil }
      return NSRect(x: x, y: y, width: width, height: height)
    }
    guard let caret = rect(args["caret"]), let composing = rect(args["composing"]) else {
      return nil
    }
    self.caret = caret
    self.composing = composing
  }
}

private final class EditorTextInput: NSView, NSTextInputClient {
  private let client: Int
  private weak var controller: EditorFlutterViewController?
  private let channel: FlutterMethodChannel
  private var keyUpMonitor: Any?
  private var isActive = false
  private var modifierFlags: NSEvent.ModifierFlags = []
  private var producedTextUpdate = false
  private var requestedCommand = false
  private var marked = NSAttributedString(string: "")
  private var selection = NSRange(location: 0, length: 0)
  var geometry: TextInputGeometry? {
    didSet { invalidateCoordinates() }
  }

  init(client: Int, controller: EditorFlutterViewController, channel: FlutterMethodChannel) {
    self.client = client
    self.controller = controller
    self.channel = channel
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) { return nil }

  override var acceptsFirstResponder: Bool { true }

  override func becomeFirstResponder() -> Bool {
    guard super.becomeFirstResponder() else { return false }
    isActive = true
    return true
  }

  override func resignFirstResponder() -> Bool {
    guard super.resignFirstResponder() else { return false }
    discardComposition()
    return true
  }

  func discardComposition() {
    guard isActive else { return }
    isActive = false
    if hasMarkedText() {
      clearMarkedText()
      publishPreedit()
    }
    inputContext?.discardMarkedText()
  }

  override func keyDown(with event: NSEvent) {
    controller?.keyDown(with: event)
  }

  override func keyUp(with event: NSEvent) {
    controller?.keyUp(with: event)
  }

  override func flagsChanged(with event: NSEvent) {
    controller?.flagsChanged(with: event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard window?.firstResponder === self else { return false }
    return controller?.dispatchKeyEquivalent(event) == true
  }

  func watchCommandReleases() {
    // AppKit skips keyUp while Command is held. Flutter's monitor applies
    // only to Flutter's own views, so deliver releases for this responder.
    keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
      guard let self, event.window?.firstResponder === self,
            event.modifierFlags.contains(.command) else { return event }
      self.keyUp(with: event)
      return nil
    }
  }

  func stopWatchingCommandReleases() {
    if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
    keyUpMonitor = nil
  }

  func invalidateCoordinates() {
    if isActive { inputContext?.invalidateCharacterCoordinates() }
  }

  func handleModifierPress(_ event: NSEvent) -> Bool {
    // Like Flutter's AppKit text input plugin, offer modifier presses to the
    // context and leave releases to the ordinary keyboard state handler.
    let pressed = event.modifierFlags.subtracting(modifierFlags)
    modifierFlags = event.modifierFlags
    if pressed.isEmpty { return false }
    return handle(event, isKeyEquivalent: false)
  }

  func handle(_ event: NSEvent, isKeyEquivalent: Bool) -> Bool {
    guard isActive, let context = inputContext else { return false }
    modifierFlags = event.modifierFlags
    let wasComposing = hasMarkedText()
    producedTextUpdate = false
    requestedCommand = false
    let consumed = context.handleEvent(event)
    if producedTextUpdate { return true }
    // AppKit can recognize a Command key equivalent without executing it.
    // Forward it to Flutter's existing shortcut and menu dispatch path.
    if requestedCommand
      || (isKeyEquivalent && !wasComposing && event.modifierFlags.contains(.command)) {
      return false
    }
    return consumed
  }

  func hasMarkedText() -> Bool { marked.length > 0 }

  func markedRange() -> NSRange {
    hasMarkedText() ? NSRange(location: 0, length: marked.length)
      : NSRange(location: NSNotFound, length: 0)
  }

  func selectedRange() -> NSRange { selection }

  func validAttributesForMarkedText() -> [NSAttributedString.Key] {
    [.markedClauseSegment, .underlineStyle, .backgroundColor]
  }

  func attributedSubstring(forProposedRange range: NSRange,
                           actualRange: NSRangePointer?) -> NSAttributedString? {
    guard let slice = boundedRange(range, length: marked.length) else { return nil }
    actualRange?.pointee = slice
    return marked.attributedSubstring(from: slice)
  }

  func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    guard isActive, let text = attributedText(string) else { return }
    producedTextUpdate = true
    let insertionOffset = boundedRange(replacementRange, length: marked.length)?.location ?? 0
    marked = replacingMarkedText(with: text, range: replacementRange)
    let withinText = boundedRange(selectedRange, length: text.length)
      ?? NSRange(location: text.length, length: 0)
    selection = NSRange(location: insertionOffset + withinText.location, length: withinText.length)
    publishPreedit()
  }

  func insertText(_ string: Any, replacementRange: NSRange) {
    guard isActive, let text = attributedText(string) else { return }
    let committed = replacingMarkedText(with: text, range: replacementRange).string
    commit(committed)
  }

  func unmarkText() {
    guard isActive, hasMarkedText() else { return }
    // An unmark keeps the text in AppKit's document. An empty marked update
    // removes the composition without committing it.
    commit(marked.string)
  }

  override func doCommand(by selector: Selector) {
    requestedCommand = true
  }

  override func insertTab(_ sender: Any?) {
    // Route Tab through Flutter's key binding handling.
    requestedCommand = true
  }

  func characterIndex(for point: NSPoint) -> Int { NSNotFound }

  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    guard let geometry, let view = controller?.view, let window = view.window else { return .zero }
    let usePreedit = hasMarkedText() && range.length > 0
    let rect = usePreedit ? geometry.composing : geometry.caret
    actualRange?.pointee = usePreedit ? markedRange()
      : NSRange(location: selection.location, length: 0)
    let y = view.isFlipped ? view.bounds.minY + rect.minY : view.bounds.maxY - rect.maxY
    let inView = NSRect(x: view.bounds.minX + rect.minX, y: y,
                        width: rect.width, height: rect.height)
    return window.convertToScreen(view.convert(inView, to: nil))
  }

  func windowLevel() -> Int { window?.level.rawValue ?? 0 }

  private func boundedRange(_ range: NSRange, length: Int) -> NSRange? {
    guard range.location != NSNotFound, (0...length).contains(range.location),
          range.length >= 0 else { return nil }
    return NSRange(location: range.location, length: min(range.length, length - range.location))
  }

  private func attributedText(_ value: Any) -> NSAttributedString? {
    if let text = value as? NSAttributedString { return text }
    return (value as? String).map { NSAttributedString(string: $0) }
  }

  private func replacingMarkedText(with text: NSAttributedString, range: NSRange)
    -> NSAttributedString {
    guard hasMarkedText(), let range = boundedRange(range, length: marked.length) else {
      return text
    }
    let updated = NSMutableAttributedString(attributedString: marked)
    updated.replaceCharacters(in: range, with: text)
    return updated
  }

  private func clearMarkedText() {
    marked = NSAttributedString(string: "")
    selection = NSRange(location: 0, length: 0)
  }

  private func commit(_ text: String) {
    producedTextUpdate = true
    if hasMarkedText() {
      clearMarkedText()
      publishPreedit()
    }
    if !text.isEmpty {
      channel.invokeMethod("commit", arguments: ["client": client, "text": text])
    }
  }

  private func publishPreedit() {
    var segments: [[String: Any]] = []
    if marked.length > 0 {
      marked.enumerateAttributes(in: markedRange()) { attrs, range, _ in
        guard attrs[.markedClauseSegment] != nil || attrs[.underlineStyle] != nil
          || attrs[.backgroundColor] != nil else { return }
        segments.append([
          "start": range.location,
          "end": NSMaxRange(range),
          "selected": attrs[.backgroundColor] != nil
            || NSIntersectionRange(range, self.selection).length > 0,
        ])
      }
    }
    channel.invokeMethod("preedit", arguments: [
      "client": client,
      "text": marked.string,
      "selectionStart": selection.location,
      "selectionEnd": NSMaxRange(selection),
      "segments": segments,
    ])
  }
}

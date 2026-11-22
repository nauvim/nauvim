import Cocoa
import CoreText
import FlutterMacOS
import WebKit

private enum PreviewKey: Equatable {
  case character(UInt32), function(UInt32)
  case escape, enter, numpadEnter, tab, backspace, delete, insert
  case up, down, left, right, home, end, pageUp, pageDown

  init?(name: String) {
    switch name {
    case "escape": self = .escape
    case "enter": self = .enter
    case "numpadenter": self = .numpadEnter
    case "tab": self = .tab
    case "backspace": self = .backspace
    case "delete": self = .delete
    case "insert": self = .insert
    case "arrowup": self = .up
    case "arrowdown": self = .down
    case "arrowleft": self = .left
    case "arrowright": self = .right
    case "home": self = .home
    case "end": self = .end
    case "pageup": self = .pageUp
    case "pagedown": self = .pageDown
    default:
      if name.first == "f", let n = UInt32(name.dropFirst()), (1...24).contains(n) {
        self = .function(n)
      } else if name.unicodeScalars.count == 1, let scalar = name.unicodeScalars.first {
        self = .character(scalar.value)
      } else { return nil }
    }
  }

  static func event(_ text: String, keyCode: UInt16) -> PreviewKey? {
    guard text.unicodeScalars.count == 1, let c = text.unicodeScalars.first else { return nil }
    switch c.value {
    case 0x1b: return .escape
    case 0x0d, 0x0a: return keyCode == 76 ? .numpadEnter : .enter
    case 0x09, 0x19: return .tab
    case 0x7f: return .backspace
    case 0xf728: return .delete
    case 0xf727: return .insert
    case 0xf700: return .up
    case 0xf701: return .down
    case 0xf702: return .left
    case 0xf703: return .right
    case 0xf729: return .home
    case 0xf72b: return .end
    case 0xf72c: return .pageUp
    case 0xf72d: return .pageDown
    case 0xf704...0xf71b: return .function(c.value - 0xf704 + 1)
    default: return .character(c.value)
    }
  }
}

private enum PreviewAction: String {
  case reload, goBack, goForward, close, focusEditor
}

private struct PreviewKeyBinding {
  let key: PreviewKey
  let lower: PreviewKey
  let upper: PreviewKey
  let modifiers: Int
  let action: PreviewAction

  init?(key name: String, modifiers: Int, action: String) {
    guard let key = PreviewKey(name: name), let action = PreviewAction(rawValue: action) else { return nil }
    self.key = key
    self.modifiers = modifiers
    self.action = action
    if case .character = key {
      self.lower = PreviewKey(name: name.lowercased()) ?? key
      self.upper = PreviewKey(name: name.uppercased()) ?? key
    } else {
      self.lower = key
      self.upper = key
    }
  }

  func matches(_ key: PreviewKey) -> Bool {
    self.key == key || lower == key || upper == key
  }
}

private struct PreviewNavigation: Equatable {
  let url: URL
  let replaceHistory: Bool
  let focus: Bool
}

private final class RequestedPreviewNavigation {
  let options: PreviewNavigation
  var navigation: WKNavigation?
  var accepted = false
  var finished = false
  var committedURL: URLComponents?

  init(_ options: PreviewNavigation) {
    self.options = options
  }
}

private class PreviewWebView: WKWebView {
  var handle: Int64 = 0
  var focusable = false
  var closeOnBlur = false
  var requestedNavigation: RequestedPreviewNavigation?
  var handleKey: ((NSEvent) -> Bool)?

  override var acceptsFirstResponder: Bool { focusable && super.acceptsFirstResponder }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if handleKey?(event) == true { return true }
    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    if handleKey?(event) != true { super.keyDown(with: event) }
  }
}

class MainFlutterWindow: NSWindow, NSWindowDelegate, WKNavigationDelegate {
  private var channel: FlutterMethodChannel?
  private var webviews: [Int64: PreviewWebView] = [:]
  private var keyBindings: [PreviewKeyBinding] = []
  private(set) var isCleanupComplete = false
  private var closeRequested = false
  private var startupModePending = false
  private var startupOpacity: CGFloat = 1
  private var applyingStartupZoom = false
  private var windowConfigured = false
  private var lastWindowSize: NSSize?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
    if let view = responder as? NSView,
       webviews.values.contains(where: {
         (!$0.focusable || $0.isHidden) && (view === $0 || view.isDescendant(of: $0))
       }) {
      return false
    }
    let focusedPreview = webviews.values.first { $0.closeOnBlur && previewHasFocus($0) }
    let accepted = super.makeFirstResponder(responder)
    if let focusedPreview, !previewHasFocus(focusedPreview) {
      closePreview(focusedPreview.handle, notify: true)
    }
    return accepted
  }

  private func previewHasFocus(_ preview: PreviewWebView) -> Bool {
    guard let responder = firstResponder as? NSView else { return false }
    return responder === preview || responder.isDescendant(of: preview)
  }

  private func restoreEditorFocus(_ preview: PreviewWebView) {
    if previewHasFocus(preview) {
      makeFirstResponder(contentViewController?.view)
    }
  }

  private func focusPreview(_ view: PreviewWebView) -> Bool {
    view.focusable && !view.isHidden && makeFirstResponder(view) && previewHasFocus(view)
  }

  private func closePreview(_ handle: Int64, notify: Bool = false) {
    guard let view = webviews.removeValue(forKey: handle) else { return }
    restoreEditorFocus(view)
    view.navigationDelegate = nil
    view.stopLoading()
    view.removeFromSuperview()
    if notify {
      channel?.invokeMethod("close_webview_requested", arguments: handle)
    }
  }

  override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
    applyingStartupZoom ? 0 : super.animationResizeTime(newFrame)
  }

  func configureInitialWindow(_ args: [String: Any]) {
    let current = contentRect(forFrameRect: frame).size
    if args["decorations"] as? String == "none" {
      styleMask.remove(.titled)
    } else {
      styleMask.insert(.titled)
    }
    if let opacity = (args["opacity"] as? NSNumber)?.doubleValue,
       opacity.isFinite, (0...1).contains(opacity) {
      startupOpacity = CGFloat(opacity)
    }
    let width = (args["width"] as? NSNumber)?.doubleValue ?? current.width
    let height = (args["height"] as? NSNumber)?.doubleValue ?? current.height
    if width.isFinite && height.isFinite && width > 0 && height > 0 {
      setContentSize(NSSize(width: width, height: height))
    }
    switch args["startup_mode"] as? String ?? "windowed" {
    case "maximized":
      if !isZoomed {
        applyingStartupZoom = true
        zoom(nil)
        applyingStartupZoom = false
      }
    case "fullscreen":
      if !styleMask.contains(.fullScreen) {
        alphaValue = 0
        startupModePending = true
        collectionBehavior.insert(.fullScreenPrimary)
        toggleFullScreen(nil)
      }
    default: break
    }
    windowConfigured = true
    if !startupModePending { alphaValue = startupOpacity }
    reportWindowSize()
  }

  func windowDidResize(_ notification: Notification) {
    reportWindowSize()
  }

  func windowDidResignKey(_ notification: Notification) {
    if let view = webviews.values.first(where: { $0.closeOnBlur && previewHasFocus($0) }) {
      closePreview(view.handle, notify: true)
    }
  }

  private func reportWindowSize() {
    guard windowConfigured && !startupModePending && isVisible else { return }
    let size = contentRect(forFrameRect: frame).size
    guard size != lastWindowSize, let channel = channel else { return }
    lastWindowSize = size
    channel.invokeMethod("window_size_changed", arguments: [Double(size.width), Double(size.height)])
  }

  func windowDidEnterFullScreen(_ notification: Notification) {
    finishStartupFullscreen()
  }

  func windowDidFailToEnterFullScreen(_ window: NSWindow) {
    finishStartupFullscreen()
  }

  private func finishStartupFullscreen() {
    guard startupModePending else { return }
    startupModePending = false
    alphaValue = startupOpacity
    reportWindowSize()
  }

  override func awakeFromNib() {
    // Keep the window ordered so Flutter and AppKit can initialize it.
    alphaValue = 0
    let controller = FlutterViewController()
    let windowFrame = frame
    contentViewController = controller
    setFrame(windowFrame, display: true)
    title = "Nauvim"
    delegate = self
    RegisterGeneratedPlugins(registry: controller)
    channel = FlutterMethodChannel(name: "io.nauvim/window", binaryMessenger: controller.engine.binaryMessenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "configure_window":
        self.configureInitialWindow(args)
      case "configure_grid":
        let cw = args["cell_width"] as? Double ?? 0
        let ch = args["cell_height"] as? Double ?? 0
        guard cw.isFinite, ch.isFinite, cw > 0, ch > 0 else { result(nil); return }
        let baseWidth = args["base_width"] as? Double ?? 0
        let baseHeight = args["base_height"] as? Double ?? 0
        let minRows = max(1, args["min_rows"] as? Int ?? 1)
        self.contentResizeIncrements = NSSize(width: cw, height: ch)
        self.contentMinSize = NSSize(width: baseWidth + cw, height: baseHeight + Double(minRows) * ch)
        if !self.startupModePending && !self.isZoomed && !self.styleMask.contains(.fullScreen) {
          let current = self.contentRect(forFrameRect: self.frame).size
          let snapped = NSSize(width: baseWidth + max(1, floor((current.width - baseWidth) / cw)) * cw,
                               height: baseHeight + max(Double(minRows), floor((current.height - baseHeight) / ch)) * ch)
          if abs(snapped.width - current.width) > 0.01 || abs(snapped.height - current.height) > 0.01 {
            self.setContentSize(snapped)
          }
        }
      case "font_candidates":
        let families = call.arguments as? [String] ?? []
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
        var files: [[String: Any]] = []
        for (index, family) in families.enumerated() {
          if family.isEmpty { continue }
          let preferred: NSFont?
          switch family.lowercased() {
          case "monospace": preferred = NSFont.userFixedPitchFont(ofSize: 12)
          case "sans-serif": preferred = NSFont.systemFont(ofSize: 12)
          case "serif": preferred = NSFont(name: "Times", size: 12)
          default: preferred = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12)
          }
          var candidates: [CTFontDescriptor] = []
          if let preferred = preferred {
            candidates.append(CTFontCopyFontDescriptor(preferred as CTFont))
          }
          if !["monospace", "sans-serif", "serif"].contains(family) {
            candidates.append(contentsOf: descriptors)
          }
          var seen = Set<String>()
          for descriptor in candidates {
            guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL,
                  let postscript = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { continue }
            if !seen.insert(url.path + "\0" + postscript).inserted { continue }
            files.append(["request": index, "path": url.path, "index": 0,
                          "postscript": postscript])
          }
        }
        result(files)
        return
      case "close":
        guard !self.isCleanupComplete else { result(nil); return }
        self.isCleanupComplete = true
        // Acknowledge Dart before closing its view and engine.
        result(nil)
        DispatchQueue.main.async { [weak self] in
          self?.close()
          NSApplication.shared.terminate(nil)
        }
        return
      case "title": self.title = args["title"] as? String ?? "Nauvim"
      case "open_webview":
        self.keyBindings = (args["key_bindings"] as? [[String: Any]] ?? []).compactMap { binding in
          guard let key = binding["key"] as? String,
                let modifiers = binding["modifiers"] as? Int,
                let action = binding["action"] as? String else { return nil }
          return PreviewKeyBinding(key: key, modifiers: modifiers, action: action)
        }
        guard let handle = args["handle"] as? Int64, let url = Self.previewURL(args["url"]) else {
          result(FlutterError(code: "url", message: "Invalid HTTP URL", details: nil)); return
        }
        let view: PreviewWebView
        if let existing = self.webviews[handle] { view = existing }
        else {
          let preview = PreviewWebView(frame: .zero)
          preview.handle = handle
          preview.focusable = args["focusable"] as? Bool ?? false
          preview.closeOnBlur = args["close_on_blur"] as? Bool ?? false
          if #available(macOS 13.3, *) { preview.isInspectable = true }
          preview.handleKey = { [weak self, weak preview, weak controller] event in
            guard let self = self, let preview = preview, let controller = controller else { return false }
            return self.previewKey(event, view: preview, handle: handle, editor: controller.view)
          }
          view = preview
          view.navigationDelegate = self
          self.webviews[handle] = view
          controller.view.addSubview(view)
          if view.load(URLRequest(url: url)) == nil {
            self.closePreview(handle)
            result(FlutterError(code: "preview_navigation", message: "WebKit declined the navigation", details: nil))
            return
          }
        }
        let x = args["x"] as? Double ?? 0
        let y = args["y"] as? Double ?? 0
        let width = args["width"] as? Double ?? 0
        let height = args["height"] as? Double ?? 0
        view.frame = NSRect(x: x, y: controller.view.bounds.height - y - height, width: width, height: height)
        view.isHidden = false
      case "navigate_webview":
        guard let handle = args["handle"] as? Int64, let view = self.webviews[handle] else {
          result(FlutterError(code: "preview_navigation", message: "The preview is unavailable", details: nil))
          return
        }
        guard let url = Self.previewURL(args["url"]) else {
          result(FlutterError(code: "url", message: "Invalid HTTP URL", details: nil))
          return
        }
        let options = PreviewNavigation(url: url,
                                        replaceHistory: args["replace_history"] as? Bool ?? false,
                                        focus: args["focus"] as? Bool ?? false)
        self.navigatePreview(view, options: options, result: result)
        return
      case "focus_webview":
        guard let handle = args["handle"] as? Int64,
              let view = self.webviews[handle], self.focusPreview(view) else {
          result(FlutterError(code: "preview_focus", message: "The preview cannot receive focus", details: nil))
          return
        }
      case "hide_webview":
        if let handle = args["handle"] as? Int64, let view = self.webviews[handle] {
          self.restoreEditorFocus(view)
          view.isHidden = true
        }
      case "close_webview":
        if let handle = args["handle"] as? Int64 {
          self.closePreview(handle)
        }
      default: result(FlutterMethodNotImplemented); return
      }
      result(nil)
    }
    super.awakeFromNib()
  }

  private static func previewURL(_ value: Any?) -> URL? {
    guard let value = value as? String, let url = URL(string: value),
          let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = url.host, !host.isEmpty else { return nil }
    return url
  }

  private static func navigationAddress(_ url: URL) -> URLComponents? {
    guard var address = URLComponents(url: url.standardized, resolvingAgainstBaseURL: false) else {
      return nil
    }
    address.scheme = address.scheme?.lowercased()
    address.host = address.host?.lowercased()
    if address.path.isEmpty { address.path = "/" }
    if (address.scheme == "http" && address.port == 80) ||
       (address.scheme == "https" && address.port == 443) {
      address.port = nil
    }
    return address
  }

  private func navigatePreview(_ view: PreviewWebView, options: PreviewNavigation, result: @escaping FlutterResult) {
    let current = view.backForwardList.currentItem.flatMap { Self.navigationAddress($0.url) }
    if let active = view.requestedNavigation, active.options == options,
       active.committedURL == nil || active.committedURL == current {
      result(nil)
      return
    }

    let request = RequestedPreviewNavigation(options)
    view.requestedNavigation = request
    if options.replaceHistory && view.backForwardList.currentItem != nil {
      // Use WebKit's location replacement so cross-origin targets retain their normal policy checks.
      view.callAsyncJavaScript("location.replace(url); return true;", arguments: ["url": options.url.absoluteString],
                               in: nil, in: .defaultClient) { [weak view] evaluation in
        switch evaluation {
        case .success:
          result(nil)
        case .failure(let error):
          if let view, view.requestedNavigation === request { view.requestedNavigation = nil }
          result(FlutterError(code: "preview_history", message: error.localizedDescription, details: nil))
        }
      }
      return
    }
    guard let navigation = view.load(URLRequest(url: options.url)) else {
      view.requestedNavigation = nil
      result(FlutterError(code: "preview_navigation", message: "WebKit declined the navigation", details: nil))
      return
    }
    request.navigation = navigation
    result(nil)
  }

  private func isFragmentNavigation(_ url: URL, in view: PreviewWebView) -> Bool {
    guard let current = view.backForwardList.currentItem?.url,
          var from = Self.navigationAddress(current), var to = Self.navigationAddress(url),
          from.fragment != to.fragment else { return false }
    from.fragment = nil
    to.fragment = nil
    return from == to
  }

  private func focusAfterAccepting(_ request: RequestedPreviewNavigation, in view: PreviewWebView) {
    guard request.options.focus, view.focusable else { return }
    channel?.invokeMethod("webview_can_focus", arguments: view.handle) { [weak self, weak view] result in
      guard let self, let view, self.webviews[view.handle] === view,
            view.requestedNavigation === request else { return }
      guard let allowed = result as? Bool else {
        let message = (result as? FlutterError)?.message ?? "Unable to check whether the preview can receive focus"
        self.reportPreviewError(view, message)
        return
      }
      if allowed && !self.focusPreview(view) {
        self.reportPreviewError(view, "The preview cannot receive focus")
      }
    }
  }

  func requestClose() {
    guard !isCleanupComplete && !closeRequested else { return }
    closeRequested = true
    channel?.invokeMethod("close_requested", arguments: nil)
  }

  private func previewKey(_ event: NSEvent, view: WKWebView, handle: Int64, editor: NSView) -> Bool {
    guard !keyBindings.isEmpty,
          let focused = firstResponder as? NSView,
          focused === view || focused.isDescendant(of: view),
          var text = event.charactersIgnoringModifiers else { return false }
    for level in 0...1 {
      let flags: NSEvent.ModifierFlags = level == 0 ? [] : .shift
      if let clue = event.characters(byApplyingModifiers: flags),
         clue.unicodeScalars.count == 1, let c = clue.unicodeScalars.first,
         (48...57).contains(c.value) || (65...90).contains(c.value) || (97...122).contains(c.value) {
        text = clue
        break
      }
    }
    guard let key = PreviewKey.event(text, keyCode: event.keyCode) else { return false }
    let flags = event.modifierFlags
    let modifiers = (flags.contains(.control) ? 1 : 0) |
                    (flags.contains(.shift) ? 2 : 0) |
                    (flags.contains(.option) ? 4 : 0) |
                    (flags.contains(.command) ? 8 : 0)
    guard let binding = keyBindings.first(where: { $0.modifiers == modifiers && $0.matches(key) }) else { return false }
    switch binding.action {
    case .reload: view.reload()
    case .goBack: view.goBack()
    case .goForward: view.goForward()
    case .focusEditor: makeFirstResponder(editor)
    case .close: closePreview(handle, notify: true)
    }
    return true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if isCleanupComplete { return true }
    requestClose()
    return false
  }
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let frame = navigationAction.targetFrame else { decisionHandler(.cancel); return }
    if !frame.isMainFrame {
      decisionHandler(.allow)
      return
    }
    guard let view = webView as? PreviewWebView, webviews[view.handle] === view,
          let url = navigationAction.request.url, let channel else {
      decisionHandler(.cancel)
      return
    }
    let request = view.requestedNavigation
    let requestedTarget = request.map {
      if $0.accepted { return false }
      return $0.options.url == url || Self.navigationAddress($0.options.url).map {
        $0 == Self.navigationAddress(url)
      } == true
    } ?? false
    let continuesRequest = request.map {
      $0.accepted && !$0.finished && navigationAction.navigationType == .other
    } ?? false
    let args: [String: Any] = ["handle": view.handle, "url": url.absoluteString]
    channel.invokeMethod("webview_allows_navigation", arguments: args) { [weak self, weak view] result in
      guard let self, let view, self.webviews[view.handle] === view else {
        decisionHandler(.cancel)
        return
      }
      let sameRequest = view.requestedNavigation === request
      guard result as? Bool == true, !requestedTarget || sameRequest else {
        if sameRequest && (requestedTarget || continuesRequest) { view.requestedNavigation = nil }
        decisionHandler(.cancel)
        return
      }
      if let request, sameRequest {
        if requestedTarget {
          request.accepted = true
          // WebKit does not send the main-frame completion callback for fragment changes.
          request.finished = self.isFragmentNavigation(url, in: view)
          decisionHandler(.allow)
          self.focusAfterAccepting(request, in: view)
          return
        }
        if !continuesRequest && (request.accepted || navigationAction.navigationType != .other) {
          view.requestedNavigation = nil
        }
      }
      decisionHandler(.allow)
    }
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    if let view = webView as? PreviewWebView, let request = view.requestedNavigation,
       request.accepted, !request.finished, request.navigation == nil {
      request.navigation = navigation
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    if let view = webView as? PreviewWebView, let request = view.requestedNavigation,
       let navigation, request.navigation === navigation {
      request.finished = true
      request.committedURL = view.backForwardList.currentItem.flatMap { Self.navigationAddress($0.url) }
    }
  }

  func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
               completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    // Nauvim's local HTTPS preview servers use process-generated self-signed certificates.
    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
       let trust = challenge.protectionSpace.serverTrust {
      completionHandler(.useCredential, URLCredential(trust: trust))
    } else { completionHandler(.performDefaultHandling, nil) }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    reportNavigationError(webView, navigation: navigation, error: error)
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    reportNavigationError(webView, navigation: navigation, error: error)
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    (webView as? PreviewWebView)?.requestedNavigation = nil
    reportPreviewError(webView, "The preview web process terminated")
  }
  private func reportNavigationError(_ webView: WKWebView, navigation: WKNavigation?, error: Error) {
    if let view = webView as? PreviewWebView, let navigation,
       view.requestedNavigation?.navigation === navigation {
      view.requestedNavigation = nil
    }
    let failure = error as NSError
    if failure.domain != NSURLErrorDomain || failure.code != NSURLErrorCancelled {
      reportPreviewError(webView, "Navigate web preview: \(error.localizedDescription)")
    }
  }
  private func reportPreviewError(_ webView: WKWebView, _ message: String) {
    guard let view = webView as? PreviewWebView, webviews[view.handle] === view else { return }
    channel?.invokeMethod("webview_error", arguments: ["handle": view.handle, "message": message])
  }
}

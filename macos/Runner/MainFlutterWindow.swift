import Cocoa
import CoreText
import FlutterMacOS
import WebKit

class MainFlutterWindow: NSWindow, NSWindowDelegate, WKNavigationDelegate {
  private var channel: FlutterMethodChannel?
  private var webviews: [Int64: WKWebView] = [:]
  private(set) var isCleanupComplete = false
  private var closeRequested = false
  private var startupModePending = false

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  func configureInitialWindow(_ args: [String: Any]) {
    let current = contentRect(forFrameRect: frame).size
    if args["decorations"] as? String == "none" {
      styleMask.remove(.titled)
    } else {
      styleMask.insert(.titled)
    }
    if let opacity = (args["opacity"] as? NSNumber)?.doubleValue,
       opacity.isFinite, (0...1).contains(opacity) {
      alphaValue = CGFloat(opacity)
    }
    let width = (args["width"] as? NSNumber)?.doubleValue ?? current.width
    let height = (args["height"] as? NSNumber)?.doubleValue ?? current.height
    if width.isFinite && height.isFinite && width > 0 && height > 0 {
      setContentSize(NSSize(width: width, height: height))
    }
    switch args["startup_mode"] as? String ?? "windowed" {
    case "maximized":
      if !isZoomed { zoom(nil) }
    case "fullscreen":
      if !styleMask.contains(.fullScreen) {
        startupModePending = true
        collectionBehavior.insert(.fullScreenPrimary)
        toggleFullScreen(nil)
      }
    default: break
    }
  }

  func windowDidEnterFullScreen(_ notification: Notification) {
    startupModePending = false
  }

  func windowDidFailToEnterFullScreen(_ window: NSWindow) {
    startupModePending = false
  }

  override func awakeFromNib() {
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
        guard let handle = args["handle"] as? Int64,
              let urlString = args["url"] as? String,
              let url = URL(string: urlString), ["http", "https"].contains(url.scheme ?? "") else {
          result(FlutterError(code: "url", message: "Invalid HTTP URL", details: nil)); return
        }
        let view: WKWebView
        if let existing = self.webviews[handle] { view = existing }
        else {
          view = WKWebView(frame: .zero)
          view.navigationDelegate = self
          self.webviews[handle] = view
          controller.view.addSubview(view)
          view.load(URLRequest(url: url))
        }
        let x = args["x"] as? Double ?? 0
        let y = args["y"] as? Double ?? 0
        let width = args["width"] as? Double ?? 0
        let height = args["height"] as? Double ?? 0
        view.frame = NSRect(x: x, y: controller.view.bounds.height - y - height, width: width, height: height)
      case "close_webview":
        if let handle = args["handle"] as? Int64 {
          if let view = self.webviews.removeValue(forKey: handle) {
            view.navigationDelegate = nil
            view.stopLoading()
            view.removeFromSuperview()
          }
        }
      default: result(FlutterMethodNotImplemented); return
      }
      result(nil)
    }
    super.awakeFromNib()
  }
  func requestClose() {
    guard !isCleanupComplete && !closeRequested else { return }
    closeRequested = true
    channel?.invokeMethod("close_requested", arguments: nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if isCleanupComplete { return true }
    requestClose()
    return false
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
    reportNavigationError(error)
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    reportNavigationError(error)
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    channel?.invokeMethod("window_error", arguments: "The preview web process terminated")
  }
  private func reportNavigationError(_ error: Error) {
    if (error as NSError).code != NSURLErrorCancelled {
      channel?.invokeMethod("window_error", arguments: "Open preview: \(error.localizedDescription)")
    }
  }
}

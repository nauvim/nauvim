import Cocoa
import FlutterMacOS
import Testing
@testable import Nauvim

private final class FullscreenWindow: MainFlutterWindow {
  var opacityAtFullscreenRequest: CGFloat?

  override func toggleFullScreen(_ sender: Any?) {
    opacityAtFullscreenRequest = alphaValue
  }
}

struct RunnerTests {

  @Test @MainActor func appliesWindowAppearanceAndDimensions() {
    _ = NSApplication.shared
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .resizable, .closable, .miniaturizable],
      backing: .buffered, defer: true)
    window.configureInitialWindow([
      "width": 960, "height": 640, "decorations": "none",
      "opacity": 0.75, "startup_mode": "windowed",
    ])
    #expect(!window.styleMask.contains(.titled))
    #expect(window.canBecomeKey)
    #expect(window.canBecomeMain)
    #expect(window.alphaValue == 0.75)
    #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 960, height: 640))
    window.configureInitialWindow(["width": 1000, "decorations": "full", "opacity": 1.0])
    #expect(window.styleMask.contains(.titled))
    #expect(window.alphaValue == 1.0)
    #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 1000, height: 640))
    window.close()
  }

  @Test(arguments: [false, true]) @MainActor
  func revealsStartupFullscreenAfterAppKitFinishes(succeeded: Bool) {
    _ = NSApplication.shared
    let window = FullscreenWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .resizable, .closable, .miniaturizable],
      backing: .buffered, defer: true)

    window.configureInitialWindow(["startup_mode": "fullscreen", "opacity": 0.75])
    #expect(window.opacityAtFullscreenRequest == 0)
    #expect(window.alphaValue == 0)

    if succeeded {
      window.windowDidEnterFullScreen(Notification(name: NSWindow.didEnterFullScreenNotification))
    } else {
      window.windowDidFailToEnterFullScreen(window)
    }
    #expect(window.alphaValue == 0.75)
    window.close()
  }

}

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    MacOSMenuBarController.shared.attach(
      binaryMessenger: flutterViewController.engine.binaryMessenger,
      window: self
    )

    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    isMovableByWindowBackground = false

    super.awakeFromNib()
  }

  override func performClose(_ sender: Any?) {
    orderOut(sender)
    MacOSMenuBarController.shared.mainWindowWasHidden()
  }

  override func close() {
    orderOut(nil)
    MacOSMenuBarController.shared.mainWindowWasHidden()
  }
}

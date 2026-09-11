import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 1080, height: 750)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.center()

    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
    let flutterViewController = FlutterViewController(project: project)
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 1080, height: 750)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.center()

    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    RegisterGeneratedPlugins(registry: flutterViewController)
    AppDelegate.shared?.registerMessenger(flutterViewController.engine.binaryMessenger)

    let windowChannel = FlutterMethodChannel(
      name: "com.sogoodviewer.window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "toggleFullScreen" {
        self?.toggleFullScreen(nil)
        result(self?.styleMask.contains(.fullScreen) ?? false)
      } else if call.method == "isFullScreen" {
        result(self?.styleMask.contains(.fullScreen) ?? false)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

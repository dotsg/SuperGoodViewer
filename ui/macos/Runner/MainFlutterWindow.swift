import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var windowChannel: FlutterMethodChannel?

  func windowDidEnterFullScreen(_ notification: Notification) {
    self.standardWindowButton(.closeButton)?.isHidden = false
    self.standardWindowButton(.miniaturizeButton)?.isHidden = false
    self.standardWindowButton(.zoomButton)?.isHidden = false
    windowChannel?.invokeMethod("onFullScreenChanged", arguments: true)
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    windowChannel?.invokeMethod("onFullScreenChanged", arguments: false)
  }

  override func awakeFromNib() {
    super.awakeFromNib()

    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
    let flutterViewController = FlutterViewController(project: project)
    self.contentViewController = flutterViewController

    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.delegate = self

    let windowAutosaveName = "SuperGoodViewerMainWindow"
    if !self.setFrameUsingName(windowAutosaveName) {
      var windowFrame = self.frame
      windowFrame.size = NSSize(width: 1080, height: 750)
      self.setFrame(windowFrame, display: true)
      self.center()
    }
    self.setFrameAutosaveName(windowAutosaveName)

    RegisterGeneratedPlugins(registry: flutterViewController)
    AppDelegate.shared?.registerMessenger(flutterViewController.engine.binaryMessenger)

    let windowChannel = FlutterMethodChannel(
      name: "com.sogoodviewer.window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.windowChannel = windowChannel
    windowChannel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "toggleFullScreen" {
        self?.toggleFullScreen(nil)
        result(self?.styleMask.contains(.fullScreen) ?? false)
      } else if call.method == "isFullScreen" {
        result(self?.styleMask.contains(.fullScreen) ?? false)
      } else if call.method == "startDragging" {
        if let currentEvent = NSApp.currentEvent {
          self?.performDrag(with: currentEvent)
        }
        result(nil)
      } else if call.method == "zoom" {
        self?.zoom(nil)
        result(nil)
      } else if call.method == "setTrafficLightsVisible" {
        let isFs = self?.styleMask.contains(.fullScreen) ?? false
        let visible = isFs ? true : ((call.arguments as? Bool) ?? true)
        self?.standardWindowButton(.closeButton)?.isHidden = !visible
        self?.standardWindowButton(.miniaturizeButton)?.isHidden = !visible
        self?.standardWindowButton(.zoomButton)?.isHidden = !visible
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

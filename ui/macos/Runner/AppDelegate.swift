import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static weak var shared: AppDelegate?
  var appChannel: FlutterMethodChannel?
  var pendingFileToOpen: String?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    AppDelegate.shared = self
    super.applicationDidFinishLaunching(notification)
    setupAppChannel()
    setupMenuBar()
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    super.application(sender, openFiles: filenames)
    guard let file = filenames.first else { return }
    if let channel = appChannel {
      channel.invokeMethod("onOpenFile", arguments: file)
    } else {
      pendingFileToOpen = file
    }
    sender.activate(ignoringOtherApps: true)
  }

  private func setupAppChannel() {
    guard let flutterVC = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.sogoodviewer.app",
      binaryMessenger: flutterVC.engine.binaryMessenger
    )
    self.appChannel = channel

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "getInitialFile":
        let file = self.pendingFileToOpen
        self.pendingFileToOpen = nil
        result(file)
      case "checkCliStatus":
        result(self.checkCliStatus())
      case "installCli":
        self.installCli(result: result)
      case "uninstallCli":
        self.uninstallCli(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    if let pending = pendingFileToOpen {
      channel.invokeMethod("onOpenFile", arguments: pending)
      pendingFileToOpen = nil
    }
  }

  private func setupMenuBar() {
    // Add "安装 'sgv' 命令行工具..." under the primary App Menu
    guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }

    // Check if already added to avoid duplicates
    if appMenu.items.contains(where: { $0.action == #selector(menuInstallCliAction) }) {
      return
    }

    let installItem = NSMenuItem(
      title: "安装 'sgv' 命令行工具...",
      action: #selector(menuInstallCliAction),
      keyEquivalent: ""
    )
    installItem.target = self

    let insertIndex = min(1, appMenu.items.count)
    appMenu.insertItem(installItem, at: insertIndex)
  }

  @objc private func menuInstallCliAction() {
    NSApp.activate(ignoringOtherApps: true)
    if let channel = appChannel {
      channel.invokeMethod("showCliDialog", arguments: nil)
    } else {
      let alert = NSAlert()
      alert.messageText = "安装 'sgv' 命令行工具"
      alert.informativeText = "请在主窗口完全加载后重试。"
      alert.runModal()
    }
  }

  // MARK: - CLI Tool Management

  private let cliSymlinkPath = "/usr/local/bin/sgv"

  private func getCliScriptPath() -> String {
    let resourcesBin = Bundle.main.bundleURL
      .appendingPathComponent("Contents/Resources/bin", isDirectory: true)
    let scriptUrl = resourcesBin.appendingPathComponent("sgv")

    let fm = FileManager.default
    if !fm.fileExists(atPath: scriptUrl.path) {
      try? fm.createDirectory(at: resourcesBin, withIntermediateDirectories: true)
      try? embeddedSgvScript.write(to: scriptUrl, atomically: true, encoding: .utf8)
      try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptUrl.path)
    }
    return scriptUrl.path
  }

  private func checkCliStatus() -> [String: Any] {
    let fm = FileManager.default
    let exists = fm.fileExists(atPath: cliSymlinkPath)
    var destination = ""
    var isCurrentApp = false

    if exists {
      if let target = try? fm.destinationOfSymbolicLink(atPath: cliSymlinkPath) {
        destination = target
        let appBundlePath = Bundle.main.bundlePath
        isCurrentApp = target.contains(appBundlePath) || target.contains("SuperGoodViewer")
      }
    }

    return [
      "isInstalled": exists,
      "path": cliSymlinkPath,
      "target": destination,
      "isCurrentApp": isCurrentApp
    ]
  }

  private func installCli(result: @escaping FlutterResult) {
    let sourcePath = getCliScriptPath()
    let fm = FileManager.default

    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sourcePath)

    // Try standard non-root link creation first
    do {
      if fm.fileExists(atPath: cliSymlinkPath) {
        try fm.removeItem(atPath: cliSymlinkPath)
      }
      try fm.createSymbolicLink(atPath: cliSymlinkPath, withDestinationPath: sourcePath)
      result(["status": "success", "path": cliSymlinkPath])
      return
    } catch {
      // Standard creation failed, prompt for admin privileges
      let appleScriptSource = """
      do shell script "mkdir -p /usr/local/bin && ln -sf '\(sourcePath)' '\(cliSymlinkPath)'" with administrator privileges
      """

      var errorDict: NSDictionary?
      if let script = NSAppleScript(source: appleScriptSource) {
        script.executeAndReturnError(&errorDict)
        if let err = errorDict {
          let errCode = err[NSAppleScript.errorNumber] as? Int ?? 0
          if errCode == -128 {
            result(["status": "cancelled", "message": "用户取消了授权"])
          } else {
            let errMsg = err[NSAppleScript.errorMessage] as? String ?? "未知权限错误"
            result(["status": "error", "message": errMsg])
          }
          return
        }
        result(["status": "success", "path": cliSymlinkPath])
      } else {
        result(["status": "error", "message": "无法初始化系统授权脚本"])
      }
    }
  }

  private func uninstallCli(result: @escaping FlutterResult) {
    let fm = FileManager.default
    guard fm.fileExists(atPath: cliSymlinkPath) else {
      result(["status": "success", "message": "未安装"])
      return
    }

    do {
      try fm.removeItem(atPath: cliSymlinkPath)
      result(["status": "success", "path": cliSymlinkPath])
    } catch {
      let appleScriptSource = """
      do shell script "rm -f '\(cliSymlinkPath)'" with administrator privileges
      """
      var errorDict: NSDictionary?
      if let script = NSAppleScript(source: appleScriptSource) {
        script.executeAndReturnError(&errorDict)
        if let err = errorDict {
          let errCode = err[NSAppleScript.errorNumber] as? Int ?? 0
          if errCode == -128 {
            result(["status": "cancelled", "message": "用户取消了授权"])
          } else {
            let errMsg = err[NSAppleScript.errorMessage] as? String ?? "未知权限错误"
            result(["status": "error", "message": errMsg])
          }
          return
        }
        result(["status": "success"])
      } else {
        result(["status": "error", "message": "无法初始化系统授权脚本"])
      }
    }
  }

  private let embeddedSgvScript = """
  #!/bin/bash
  SOURCE="${BASH_SOURCE[0]}"
  while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  APP_DIR="$(cd "$SCRIPT_DIR/../../.." >/dev/null 2>&1 && pwd)"

  if [ ! -d "$APP_DIR" ] || [[ "$APP_DIR" != *".app" ]]; then
    if [ -d "/Applications/SuperGoodViewer.app" ]; then
      APP_DIR="/Applications/SuperGoodViewer.app"
    elif [ -d "$HOME/Applications/SuperGoodViewer.app" ]; then
      APP_DIR="$HOME/Applications/SuperGoodViewer.app"
    elif [ -d "/Applications/超好读.app" ]; then
      APP_DIR="/Applications/超好读.app"
    else
      APP_DIR="SuperGoodViewer"
    fi
  fi

  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "SuperGoodViewer (超好读) CLI Launcher"
    echo ""
    echo "Usage:"
    echo "  sgv [file.md ...]      Open markdown file(s) in SuperGoodViewer"
    echo "  sgv                    Launch or focus SuperGoodViewer"
    echo "  sgv -h, --help         Show this help message"
    exit 0
  fi

  if [ $# -eq 0 ]; then
    open -a "$APP_DIR"
  else
    for f in "$@"; do
      if [ -e "$f" ]; then
        ABS_PATH="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
        open -a "$APP_DIR" "$ABS_PATH"
      else
        echo "sgv: error: file not found: $f" >&2
        exit 1
      fi
    done
  fi
  """
}

import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static weak var shared: AppDelegate?
  var appChannel: FlutterMethodChannel?
  var pendingFileToOpen: String?

  override init() {
    super.init()
    AppDelegate.shared = self
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    AppDelegate.shared = self
    setupMenuBar()

    // Backup registration if MainFlutterWindow hasn't called registerMessenger yet
    if appChannel == nil,
       let flutterVC = mainFlutterWindow?.contentViewController as? FlutterViewController {
      registerMessenger(flutterVC.engine.binaryMessenger)
    }
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    NSLog("[SuperGoodViewer] application openFile: %@", filename)
    handleOpenFile(filename)
    sender.activate(ignoringOtherApps: true)
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    NSLog("[SuperGoodViewer] application openFiles count: %d", filenames.count)
    for file in filenames {
      handleOpenFile(file)
    }
    sender.reply(toOpenOrPrint: .success)
    sender.activate(ignoringOtherApps: true)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    NSLog("[SuperGoodViewer] application open urls: %@", urls)
    for url in urls {
      if url.scheme == "sgv" || url.scheme == "supergoodviewer" {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let path = components.queryItems?.first(where: { $0.name == "path" })?.value {
          handleOpenFile(path)
          continue
        }
        if !url.path.isEmpty {
          handleOpenFile(url.path)
          continue
        }
      }
      if url.isFileURL {
        handleOpenFile(url.path)
      }
    }
    application.activate(ignoringOtherApps: true)
  }

  private func handleOpenFile(_ path: String) {
    let cleanPath = (path as NSString).standardizingPath
    NSLog("[SuperGoodViewer] handleOpenFile target: %@", cleanPath)
    if let channel = appChannel {
      channel.invokeMethod("onOpenFile", arguments: cleanPath)
    } else {
      pendingFileToOpen = cleanPath
    }
  }

  func registerMessenger(_ messenger: FlutterBinaryMessenger) {
    if appChannel != nil { return }
    let channel = FlutterMethodChannel(
      name: "com.sogoodviewer.app",
      binaryMessenger: messenger
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
    guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }

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
      alert.informativeText = "主窗口正在加载中，请稍后重试。"
      alert.runModal()
    }
  }

  // MARK: - CLI Tool Management

  private let cliSymlinkPath = "/usr/local/bin/sgv"
  private let cliToolSymlinkPath = "/usr/local/bin/sgv-cli"

  private func getCliScriptPath() -> String {
    let resourcesBin = Bundle.main.bundleURL
      .appendingPathComponent("Contents/Resources/bin", isDirectory: true)
    let scriptUrl = resourcesBin.appendingPathComponent("sgv")

    let fm = FileManager.default
    if fm.fileExists(atPath: scriptUrl.path) {
      return scriptUrl.path
    }

    // Fallback: If running in dev mode or script not in bundle, write to Application Support
    if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      let sgvDir = appSupport.appendingPathComponent("SuperGoodViewer/bin", isDirectory: true)
      let targetFile = sgvDir.appendingPathComponent("sgv")
      try? fm.createDirectory(at: sgvDir, withIntermediateDirectories: true)
      try? embeddedSgvScript.write(to: targetFile, atomically: true, encoding: .utf8)
      try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetFile.path)
      return targetFile.path
    }

    return scriptUrl.path
  }

  private func getCliBinaryPath() -> String? {
    let resourcesBin = Bundle.main.bundleURL
      .appendingPathComponent("Contents/Resources/bin", isDirectory: true)
    let binaryUrl = resourcesBin.appendingPathComponent("sgv-cli")

    let fm = FileManager.default
    if fm.fileExists(atPath: binaryUrl.path) {
      return binaryUrl.path
    }
    return nil
  }

  private func itemExists(atPath path: String) -> Bool {
    return (try? FileManager.default.attributesOfItem(atPath: path)) != nil
  }

  private func checkCliStatus() -> [String: Any] {
    let fm = FileManager.default
    let sgvExists = itemExists(atPath: cliSymlinkPath)
    let cliToolExists = itemExists(atPath: cliToolSymlinkPath)
    let cliBinPath = getCliBinaryPath()

    let isInstalled = (cliBinPath != nil) ? (sgvExists && cliToolExists) : sgvExists
    let isPartial = !isInstalled && (sgvExists || cliToolExists)
    var destination = ""
    var isCurrentApp = false

    if sgvExists {
      if let target = try? fm.destinationOfSymbolicLink(atPath: cliSymlinkPath) {
        destination = target
        let appBundlePath = Bundle.main.bundlePath
        let sgvMatches = target.contains(appBundlePath) || target.contains("SuperGoodViewer")

        var cliToolMatches = true
        if let bin = cliBinPath {
          if let toolTarget = try? fm.destinationOfSymbolicLink(atPath: cliToolSymlinkPath) {
            cliToolMatches = (toolTarget == bin) || toolTarget.contains(appBundlePath) || toolTarget.contains("SuperGoodViewer")
          } else {
            cliToolMatches = false
          }
        }

        isCurrentApp = sgvMatches && cliToolMatches
      }
    }

    var res: [String: Any] = [
      "isInstalled": isInstalled,
      "isPartial": isPartial,
      "path": cliSymlinkPath,
      "target": destination,
      "isCurrentApp": isCurrentApp
    ]
    if isPartial {
      res["warningCode"] = "incomplete_tools"
      res["warning"] = "安装不完整 (部分工具未就绪)"
    }
    return res
  }

  private func installCli(result: @escaping FlutterResult) {
    let sourcePath = getCliScriptPath()
    let cliBinPath = getCliBinaryPath()
    let fm = FileManager.default

    let oldSgvDestination = try? fm.destinationOfSymbolicLink(atPath: cliSymlinkPath)
    let backupSgvPath: String? = (oldSgvDestination == nil && itemExists(atPath: cliSymlinkPath))
        ? (NSTemporaryDirectory() as NSString).appendingPathComponent("sgv_backup_\(ProcessInfo.processInfo.globallyUniqueString)")
        : nil
    if let backup = backupSgvPath {
      try? fm.copyItem(atPath: cliSymlinkPath, toPath: backup)
    }

    let oldCliToolDestination = try? fm.destinationOfSymbolicLink(atPath: cliToolSymlinkPath)
    let backupCliToolPath: String? = (oldCliToolDestination == nil && itemExists(atPath: cliToolSymlinkPath))
        ? (NSTemporaryDirectory() as NSString).appendingPathComponent("sgv_cli_backup_\(ProcessInfo.processInfo.globallyUniqueString)")
        : nil
    if let backup = backupCliToolPath {
      try? fm.copyItem(atPath: cliToolSymlinkPath, toPath: backup)
    }

    defer {
      if let backup = backupSgvPath {
        try? fm.removeItem(atPath: backup)
      }
      if let backup = backupCliToolPath {
        try? fm.removeItem(atPath: backup)
      }
    }

    func targetExists(_ target: String, relativeTo linkPath: String) -> Bool {
      let fullPath = (target as NSString).isAbsolutePath
          ? target
          : ((linkPath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(target)
      return fm.fileExists(atPath: fullPath)
    }

    func restoreOldLinks() {
      if !itemExists(atPath: cliSymlinkPath) {
        if let old = oldSgvDestination, targetExists(old, relativeTo: cliSymlinkPath) {
          try? fm.createSymbolicLink(atPath: cliSymlinkPath, withDestinationPath: old)
        } else if let backup = backupSgvPath, fm.fileExists(atPath: backup) {
          try? fm.copyItem(atPath: backup, toPath: cliSymlinkPath)
        }
      }
      if !itemExists(atPath: cliToolSymlinkPath) {
        if let old = oldCliToolDestination, targetExists(old, relativeTo: cliToolSymlinkPath) {
          try? fm.createSymbolicLink(atPath: cliToolSymlinkPath, withDestinationPath: old)
        } else if let backup = backupCliToolPath, fm.fileExists(atPath: backup) {
          try? fm.copyItem(atPath: backup, toPath: cliToolSymlinkPath)
        }
      }
    }

    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sourcePath)
    if let bin = cliBinPath {
      try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin)
    }

    // Try non-root symlink creation first
    do {
      if itemExists(atPath: cliSymlinkPath) {
        try fm.removeItem(atPath: cliSymlinkPath)
      }
      try fm.createSymbolicLink(atPath: cliSymlinkPath, withDestinationPath: sourcePath)

      if let bin = cliBinPath {
        if itemExists(atPath: cliToolSymlinkPath) {
          try fm.removeItem(atPath: cliToolSymlinkPath)
        }
        try fm.createSymbolicLink(atPath: cliToolSymlinkPath, withDestinationPath: bin)
      }

      result(["status": "success", "path": cliSymlinkPath])
      return
    } catch {
      // Standard creation failed (needs admin permissions). Use AppleScript.
      var scriptCommands = "mkdir -p /usr/local/bin && ln -sf '\(sourcePath)' '\(cliSymlinkPath)'"
      if let bin = cliBinPath {
        scriptCommands += " && ln -sf '\(bin)' '\(cliToolSymlinkPath)'"
      }
      let appleScriptSource = """
      do shell script "\(scriptCommands)" with administrator privileges
      """

      var errorDict: NSDictionary?
      if let script = NSAppleScript(source: appleScriptSource) {
        script.executeAndReturnError(&errorDict)
        if let err = errorDict {
          restoreOldLinks()
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
        restoreOldLinks()
        result(["status": "error", "message": "无法初始化系统授权脚本"])
      }
    }
  }

  private func uninstallCli(result: @escaping FlutterResult) {
    let fm = FileManager.default
    guard itemExists(atPath: cliSymlinkPath) || itemExists(atPath: cliToolSymlinkPath) else {
      result(["status": "success", "message": "未安装"])
      return
    }

    do {
      if itemExists(atPath: cliSymlinkPath) {
        try fm.removeItem(atPath: cliSymlinkPath)
      }
      if itemExists(atPath: cliToolSymlinkPath) {
        try fm.removeItem(atPath: cliToolSymlinkPath)
      }
      result(["status": "success", "path": cliSymlinkPath])
    } catch {
      let appleScriptSource = """
      do shell script "rm -f '\(cliSymlinkPath)' '\(cliToolSymlinkPath)'" with administrator privileges
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

  # Check for headless export CLI
  CLI_BIN=""
  if [ -x "$SCRIPT_DIR/sgv-cli" ]; then
    CLI_BIN="$SCRIPT_DIR/sgv-cli"
  elif [ -x "$APP_DIR/Contents/Resources/bin/sgv-cli" ]; then
    CLI_BIN="$APP_DIR/Contents/Resources/bin/sgv-cli"
  elif command -v sgv-cli >/dev/null 2>&1; then
    CLI_BIN="$(command -v sgv-cli)"
  fi

  IS_EXPORT=false
  if [ "$1" = "export" ]; then
    IS_EXPORT=true
  else
    for arg in "$@"; do
      case "$arg" in
        -o | --output | --export | -f | --format | --page-format | --fluid | -t | --theme | --dark | -s | --font-size | --title | -r | --recursive | --no-recursive | --image-cache-dir)
          IS_EXPORT=true
          break
          ;;
      esac
    done
  fi

  if [ "$IS_EXPORT" = true ]; then
    if [ -n "$CLI_BIN" ] && [ -x "$CLI_BIN" ]; then
      exec "$CLI_BIN" "$@"
    else
      echo "sgv: error: headless export tool 'sgv-cli' not found" >&2
      exit 1
    fi
  fi

  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "SuperGoodViewer (超好读) CLI Launcher & Tool"
    echo ""
    echo "Usage:"
    echo "  sgv [file.md ...]               Open markdown file(s) in SuperGoodViewer GUI"
    echo "  sgv export <path>... [options]  Export markdown file(s) or directory to PDF"
    echo "  sgv <file.md> -o <output.pdf>   Export single markdown file to PDF"
    echo "  sgv                             Launch or focus SuperGoodViewer GUI"
    echo "  sgv -h, --help                  Show this help message"
    exit 0
  fi

  SOCK_FILE="/tmp/sgv_${USER:-user}.sock"

  if [ $# -eq 0 ]; then
    open -a "$APP_DIR"
  else
    for f in "$@"; do
      if [ -e "$f" ]; then
        ABS_PATH="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
        if [ -S "$SOCK_FILE" ]; then
          echo "$ABS_PATH" | nc -U -w 1 "$SOCK_FILE" >/dev/null 2>&1
          open -a "$APP_DIR"
        else
          open -a "$APP_DIR" "$ABS_PATH" --args "$ABS_PATH"
        fi
      else
        echo "sgv: error: file not found: $f" >&2
        exit 1
      fi
    done
  fi
  """
}

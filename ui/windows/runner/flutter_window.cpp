#include "flutter_window.h"

#include <optional>
#include <fstream>
#include <filesystem>
#include <shlobj.h>

#include "utils.h"
#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  SetupMethodChannels();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  app_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetupMethodChannels() {
  auto messenger = flutter_controller_->engine()->messenger();

  // 1. com.sogoodviewer.window Channel
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.sogoodviewer.window", &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "toggleFullScreen") {
          bool is_fs = this->ToggleFullScreen();
          result->Success(flutter::EncodableValue(is_fs));
        } else if (call.method_name() == "isFullScreen") {
          result->Success(flutter::EncodableValue(this->is_full_screen_));
        } else if (call.method_name() == "startDragging") {
          this->StartDragging();
          result->Success();
        } else if (call.method_name() == "zoom") {
          this->Zoom();
          result->Success();
        } else if (call.method_name() == "setTrafficLightsVisible") {
          // No traffic lights on Windows; no-op
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  // 2. com.sogoodviewer.app Channel
  app_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.sogoodviewer.app", &flutter::StandardMethodCodec::GetInstance());

  app_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getInitialFile") {
          if (!pending_file_.empty()) {
            std::string file = pending_file_;
            pending_file_.clear();
            result->Success(flutter::EncodableValue(file));
          } else {
            result->Success();
          }
        } else if (call.method_name() == "checkCliStatus") {
          result->Success(flutter::EncodableValue(this->CheckCliStatus()));
        } else if (call.method_name() == "installCli") {
          result->Success(flutter::EncodableValue(this->InstallCli()));
        } else if (call.method_name() == "uninstallCli") {
          result->Success(flutter::EncodableValue(this->UninstallCli()));
        } else {
          result->NotImplemented();
        }
      });

  if (!pending_file_.empty()) {
    app_channel_->InvokeMethod("onOpenFile",
                               std::make_unique<flutter::EncodableValue>(pending_file_));
    pending_file_.clear();
  }
}

bool FlutterWindow::ToggleFullScreen() {
  HWND hwnd = GetHandle();
  if (!hwnd) return false;

  if (!is_full_screen_) {
    saved_placement_.length = sizeof(WINDOWPLACEMENT);
    ::GetWindowPlacement(hwnd, &saved_placement_);
    saved_style_ = ::GetWindowLong(hwnd, GWL_STYLE);
    saved_ex_style_ = ::GetWindowLong(hwnd, GWL_EXSTYLE);

    MONITORINFO mi = { sizeof(mi) };
    if (::GetMonitorInfo(::MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY), &mi)) {
      ::SetWindowLong(hwnd, GWL_STYLE, saved_style_ & ~WS_OVERLAPPEDWINDOW);
      ::SetWindowPos(hwnd, HWND_TOP,
                     mi.rcMonitor.left, mi.rcMonitor.top,
                     mi.rcMonitor.right - mi.rcMonitor.left,
                     mi.rcMonitor.bottom - mi.rcMonitor.top,
                     SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
      is_full_screen_ = true;
    }
  } else {
    ::SetWindowLong(hwnd, GWL_STYLE, saved_style_);
    ::SetWindowLong(hwnd, GWL_EXSTYLE, saved_ex_style_);
    ::SetWindowPlacement(hwnd, &saved_placement_);
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    is_full_screen_ = false;
  }

  if (window_channel_) {
    window_channel_->InvokeMethod("onFullScreenChanged",
                                  std::make_unique<flutter::EncodableValue>(is_full_screen_));
  }
  return is_full_screen_;
}

void FlutterWindow::StartDragging() {
  HWND hwnd = GetHandle();
  if (hwnd) {
    ::ReleaseCapture();
    ::SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
  }
}

void FlutterWindow::Zoom() {
  HWND hwnd = GetHandle();
  if (hwnd) {
    if (::IsZoomed(hwnd)) {
      ::ShowWindow(hwnd, SW_RESTORE);
    } else {
      ::ShowWindow(hwnd, SW_MAXIMIZE);
    }
  }
}

void FlutterWindow::HandleOpenFile(const std::string& path) {
  if (app_channel_) {
    app_channel_->InvokeMethod("onOpenFile",
                               std::make_unique<flutter::EncodableValue>(path));
  } else {
    pending_file_ = path;
  }
  HWND hwnd = GetHandle();
  if (hwnd) {
    ::SetForegroundWindow(hwnd);
    if (::IsIconic(hwnd)) {
      ::ShowWindow(hwnd, SW_RESTORE);
    }
  }
}

std::wstring FlutterWindow::GetInstalledCliPath() {
  PWSTR local_app_data = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local_app_data))) {
    std::wstring base_path(local_app_data);
    CoTaskMemFree(local_app_data);

    // Prefer WindowsApps (automatically on PATH in Windows 10/11)
    std::wstring winapps = base_path + L"\\Microsoft\\WindowsApps";
    if (std::filesystem::exists(winapps)) {
      return winapps + L"\\sgv.cmd";
    }

    std::wstring fallback_dir = base_path + L"\\SuperGoodViewer\\bin";
    std::filesystem::create_directories(fallback_dir);
    return fallback_dir + L"\\sgv.cmd";
  }
  return L"";
}

flutter::EncodableMap FlutterWindow::CheckCliStatus() {
  std::wstring cli_path = GetInstalledCliPath();
  bool exists = !cli_path.empty() && std::filesystem::exists(cli_path);

  wchar_t exe_buf[MAX_PATH] = {0};
  GetModuleFileNameW(nullptr, exe_buf, MAX_PATH);
  std::wstring exe_path(exe_buf);

  std::string path_utf8 = Utf8FromUtf16(cli_path.c_str());
  std::string target_utf8 = Utf8FromUtf16(exe_path.c_str());

  bool is_current_app = false;
  if (exists) {
    std::ifstream file(cli_path);
    if (file.is_open()) {
      std::string content((std::istreambuf_iterator<char>(file)),
                          std::istreambuf_iterator<char>());
      if (content.find(target_utf8) != std::string::npos ||
          content.find("SuperGoodViewer.exe") != std::string::npos) {
        is_current_app = true;
      }
    }
  }

  flutter::EncodableMap res;
  res[flutter::EncodableValue("isInstalled")] = flutter::EncodableValue(exists);
  res[flutter::EncodableValue("path")] = flutter::EncodableValue(path_utf8);
  res[flutter::EncodableValue("target")] = flutter::EncodableValue(target_utf8);
  res[flutter::EncodableValue("isCurrentApp")] = flutter::EncodableValue(is_current_app);
  return res;
}

flutter::EncodableMap FlutterWindow::InstallCli() {
  std::wstring cli_path = GetInstalledCliPath();
  flutter::EncodableMap res;
  if (cli_path.empty()) {
    res[flutter::EncodableValue("status")] = flutter::EncodableValue("error");
    res[flutter::EncodableValue("message")] = flutter::EncodableValue("无法定位安装目录");
    return res;
  }

  wchar_t exe_buf[MAX_PATH] = {0};
  GetModuleFileNameW(nullptr, exe_buf, MAX_PATH);
  std::wstring exe_path(exe_buf);
  std::string exe_utf8 = Utf8FromUtf16(exe_path.c_str());
  std::string cli_path_utf8 = Utf8FromUtf16(cli_path.c_str());

  std::ofstream file(cli_path, std::ios::trunc);
  if (!file.is_open()) {
    res[flutter::EncodableValue("status")] = flutter::EncodableValue("error");
    res[flutter::EncodableValue("message")] = flutter::EncodableValue("无法写入脚本文件");
    return res;
  }

  file << "@echo off\n"
       << "setlocal enabledelayedexpansion\n"
       << "set \"EXE_PATH=" << exe_utf8 << "\"\n"
       << "if \"%~1\"==\"\" (\n"
       << "    start \"\" \"!EXE_PATH!\"\n"
       << "    exit /b 0\n"
       << ")\n"
       << "if \"%~1\"==\"-h\" goto help\n"
       << "if \"%~1\"==\"--help\" goto help\n"
       << "set \"TARGET=%~f1\"\n"
       << "if not exist \"!TARGET!\" (\n"
       << "    echo sgv: error: file not found: %~1 >&2\n"
       << "    exit /b 1\n"
       << ")\n"
       << "start \"\" \"!EXE_PATH!\" \"!TARGET!\"\n"
       << "exit /b 0\n"
       << ":help\n"
       << "echo SuperGoodViewer (超好读) CLI Launcher\n"
       << "echo.\n"
       << "echo Usage:\n"
       << "echo   sgv [file.md ...]      Open markdown file(s) in SuperGoodViewer\n"
       << "echo   sgv                    Launch or focus SuperGoodViewer\n"
       << "echo   sgv -h, --help         Show this help message\n"
       << "exit /b 0\n";
  file.close();

  // Also write sgv.ps1
  std::wstring ps1_path = cli_path.substr(0, cli_path.find_last_of(L'.')) + L".ps1";
  std::ofstream ps1_file(ps1_path, std::ios::trunc);
  if (ps1_file.is_open()) {
    ps1_file << "param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files, [switch]$Help)\n"
             << "if ($Help) { Write-Host 'SuperGoodViewer (超好读) CLI Launcher'; exit 0 }\n"
             << "if (-not $Files) { Start-Process '" << exe_utf8 << "'; exit 0 }\n"
             << "foreach ($f in $Files) { if (Test-Path $f) { Start-Process '" << exe_utf8 << "' -ArgumentList \"`\"$((Resolve-Path $f).Path)`\"\" } else { Write-Error \"sgv: file not found: $f\"; exit 1 } }\n";
    ps1_file.close();
  }

  res[flutter::EncodableValue("status")] = flutter::EncodableValue("success");
  res[flutter::EncodableValue("path")] = flutter::EncodableValue(cli_path_utf8);
  return res;
}

flutter::EncodableMap FlutterWindow::UninstallCli() {
  std::wstring cli_path = GetInstalledCliPath();
  flutter::EncodableMap res;
  if (!cli_path.empty() && std::filesystem::exists(cli_path)) {
    std::filesystem::remove(cli_path);
  }
  std::wstring ps1_path = cli_path.substr(0, cli_path.find_last_of(L'.')) + L".ps1";
  if (!ps1_path.empty() && std::filesystem::exists(ps1_path)) {
    std::filesystem::remove(ps1_path);
  }
  res[flutter::EncodableValue("status")] = flutter::EncodableValue("success");
  return res;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_COPYDATA: {
      auto* cds = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (cds && cds->dwData == 0x53475631 && cds->lpData) {
        const char* path_str = static_cast<const char*>(cds->lpData);
        HandleOpenFile(std::string(path_str));
        return TRUE;
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

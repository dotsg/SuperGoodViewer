#include "flutter_window.h"

#include <optional>
#include <fstream>
#include <filesystem>
#include <shlobj.h>
#include <algorithm>
#include <vector>

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

namespace {

bool CanWriteToDir(const std::wstring& dir) {
  if (dir.empty() || !std::filesystem::exists(dir)) return false;
  std::wstring probe = dir + L"\\.sgv_probe_" + std::to_wstring(::GetCurrentProcessId());
  HANDLE h = ::CreateFileW(probe.c_str(), GENERIC_WRITE, 0, nullptr,
                           CREATE_ALWAYS,
                           FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE,
                           nullptr);
  if (h != INVALID_HANDLE_VALUE) {
    ::CloseHandle(h);
    return true;
  }
  return false;
}

void AddToUserPathIfMissing(const std::wstring& dir_to_add) {
  HKEY hkey;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, L"Environment", 0, KEY_READ | KEY_WRITE, &hkey) == ERROR_SUCCESS) {
    DWORD type = 0;
    DWORD size = 0;
    if (::RegQueryValueExW(hkey, L"Path", nullptr, &type, nullptr, &size) == ERROR_SUCCESS && size > 0) {
      std::vector<wchar_t> buffer(size / sizeof(wchar_t) + 1);
      if (::RegQueryValueExW(hkey, L"Path", nullptr, &type, reinterpret_cast<LPBYTE>(buffer.data()), &size) == ERROR_SUCCESS) {
        std::wstring current_path(buffer.data());
        std::wstring lower_path = current_path;
        std::wstring lower_dir = dir_to_add;
        std::transform(lower_path.begin(), lower_path.end(), lower_path.begin(), ::towlower);
        std::transform(lower_dir.begin(), lower_dir.end(), lower_dir.begin(), ::towlower);
        if (lower_path.find(lower_dir) == std::wstring::npos) {
          std::wstring new_path = current_path;
          if (!new_path.empty() && new_path.back() != L';') {
            new_path += L';';
          }
          new_path += dir_to_add;
          ::RegSetValueExW(hkey, L"Path", 0, type ? type : REG_EXPAND_SZ,
                           reinterpret_cast<const BYTE*>(new_path.c_str()),
                           static_cast<DWORD>((new_path.size() + 1) * sizeof(wchar_t)));
          DWORD_PTR result;
          ::SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                                reinterpret_cast<LPARAM>(L"Environment"),
                                SMTO_ABORTIFHUNG, 3000, &result);
        }
      }
    } else {
      ::RegSetValueExW(hkey, L"Path", 0, REG_EXPAND_SZ,
                       reinterpret_cast<const BYTE*>(dir_to_add.c_str()),
                       static_cast<DWORD>((dir_to_add.size() + 1) * sizeof(wchar_t)));
      DWORD_PTR result;
      ::SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                            reinterpret_cast<LPARAM>(L"Environment"),
                            SMTO_ABORTIFHUNG, 3000, &result);
    }
    ::RegCloseKey(hkey);
  }
}

void RemoveFromUserPathIfPresent(const std::wstring& dir_to_remove) {
  HKEY hkey;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, L"Environment", 0, KEY_READ | KEY_WRITE, &hkey) == ERROR_SUCCESS) {
    DWORD type = 0;
    DWORD size = 0;
    if (::RegQueryValueExW(hkey, L"Path", nullptr, &type, nullptr, &size) == ERROR_SUCCESS && size > 0) {
      std::vector<wchar_t> buffer(size / sizeof(wchar_t) + 1);
      if (::RegQueryValueExW(hkey, L"Path", nullptr, &type, reinterpret_cast<LPBYTE>(buffer.data()), &size) == ERROR_SUCCESS) {
        std::wstring current_path(buffer.data());
        std::wstring lower_dir = dir_to_remove;
        std::transform(lower_dir.begin(), lower_dir.end(), lower_dir.begin(), ::towlower);
        std::wstring new_path;
        size_t start = 0;
        bool changed = false;
        while (start < current_path.size()) {
          size_t end = current_path.find(L';', start);
          if (end == std::wstring::npos) end = current_path.size();
          std::wstring segment = current_path.substr(start, end - start);
          std::wstring lower_segment = segment;
          std::transform(lower_segment.begin(), lower_segment.end(), lower_segment.begin(), ::towlower);
          if (lower_segment != lower_dir && !segment.empty()) {
            if (!new_path.empty()) new_path += L';';
            new_path += segment;
          } else if (lower_segment == lower_dir) {
            changed = true;
          }
          start = end + 1;
        }
        if (changed) {
          ::RegSetValueExW(hkey, L"Path", 0, type ? type : REG_EXPAND_SZ,
                           reinterpret_cast<const BYTE*>(new_path.c_str()),
                           static_cast<DWORD>((new_path.size() + 1) * sizeof(wchar_t)));
          DWORD_PTR result;
          ::SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                                reinterpret_cast<LPARAM>(L"Environment"),
                                SMTO_ABORTIFHUNG, 3000, &result);
        }
      }
    }
    ::RegCloseKey(hkey);
  }
}

void RemoveCliFiles(const std::wstring& cmd_path) {
  if (cmd_path.empty()) return;
  std::error_code ec;
  if (std::filesystem::exists(cmd_path, ec)) {
    std::filesystem::remove(cmd_path, ec);
  }
  size_t dot_pos = cmd_path.find_last_of(L'.');
  if (dot_pos != std::wstring::npos) {
    std::wstring ps1_path = cmd_path.substr(0, dot_pos) + L".ps1";
    if (std::filesystem::exists(ps1_path, ec)) {
      std::filesystem::remove(ps1_path, ec);
    }
  }
}

}  // namespace

std::wstring FlutterWindow::GetInstalledCliPath() {
  PWSTR local_app_data = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local_app_data))) {
    std::wstring base_path(local_app_data);
    CoTaskMemFree(local_app_data);

    // 1. If already installed in either location, return the existing script path
    std::wstring custom_dir = base_path + L"\\SuperGoodViewer\\bin";
    std::wstring custom_cmd = custom_dir + L"\\sgv.cmd";
    if (std::filesystem::exists(custom_cmd)) {
      return custom_cmd;
    }

    std::wstring winapps_dir = base_path + L"\\Microsoft\\WindowsApps";
    std::wstring winapps_cmd = winapps_dir + L"\\sgv.cmd";
    if (std::filesystem::exists(winapps_cmd)) {
      return winapps_cmd;
    }

    // 2. Not yet installed: prefer WindowsApps only if writable, otherwise use SuperGoodViewer\\bin
    if (CanWriteToDir(winapps_dir)) {
      return winapps_cmd;
    }

    std::filesystem::create_directories(custom_dir);
    return custom_cmd;
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
      // Point 2: Exact check against target executable path, no loose fallback substring
      if (content.find(target_utf8) != std::string::npos) {
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

  std::filesystem::path parent_dir = std::filesystem::path(cli_path).parent_path();
  std::error_code ec;
  std::filesystem::create_directories(parent_dir, ec);

  std::ofstream file(cli_path, std::ios::trunc);
  if (!file.is_open()) {
    // If writing to selected path failed (e.g. WindowsApps ACL lock), fallback to SuperGoodViewer\\bin
    PWSTR local_app_data = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local_app_data))) {
      std::wstring fallback_dir = std::wstring(local_app_data) + L"\\SuperGoodViewer\\bin";
      CoTaskMemFree(local_app_data);
      std::filesystem::create_directories(fallback_dir, ec);
      cli_path = fallback_dir + L"\\sgv.cmd";
      file.open(cli_path, std::ios::trunc);
    }
  }

  if (!file.is_open()) {
    res[flutter::EncodableValue("status")] = flutter::EncodableValue("error");
    res[flutter::EncodableValue("message")] = flutter::EncodableValue("无法写入脚本文件");
    return res;
  }

  // Write sgv.cmd with full multi-argument looping and chcp 65001 to prevent mojibake
  file << "@echo off\n"
       << "setlocal enabledelayedexpansion\n"
       << "set \"EXE_PATH=" << exe_utf8 << "\"\n"
       << "if \"%~1\"==\"\" (\n"
       << "    start \"\" \"!EXE_PATH!\"\n"
       << "    exit /b 0\n"
       << ")\n"
       << "if \"%~1\"==\"-h\" goto help\n"
       << "if \"%~1\"==\"--help\" goto help\n"
       << "if \"%~1\"==\"/?\" goto help\n"
       << ":loop\n"
       << "if \"%~1\"==\"\" goto done\n"
       << "set \"TARGET_FILE=%~f1\"\n"
       << "if not exist \"!TARGET_FILE!\" (\n"
       << "    echo sgv: error: file not found: %~1 >&2\n"
       << "    exit /b 1\n"
       << ")\n"
       << "start \"\" \"!EXE_PATH!\" \"!TARGET_FILE!\"\n"
       << "shift\n"
       << "goto loop\n"
       << ":done\n"
       << "exit /b 0\n"
       << ":help\n"
       << "chcp 65001 >nul 2>&1\n"
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
    ps1_file << "param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files, [switch]$Help, [switch]$h)\n"
             << "if ($Help -or $h) {\n"
             << "    Write-Host 'SuperGoodViewer (超好读) CLI Launcher'\n"
             << "    Write-Host ''\n"
             << "    Write-Host 'Usage:'\n"
             << "    Write-Host '  sgv [file.md ...]      Open markdown file(s) in SuperGoodViewer'\n"
             << "    Write-Host '  sgv                    Launch or focus SuperGoodViewer'\n"
             << "    Write-Host '  sgv -h, -Help          Show this help message'\n"
             << "    exit 0\n"
             << "}\n"
             << "if (-not $Files) { Start-Process '" << exe_utf8 << "'; exit 0 }\n"
             << "foreach ($f in $Files) {\n"
             << "    if (Test-Path $f) {\n"
             << "        Start-Process '" << exe_utf8 << "' -ArgumentList \"`\"$((Resolve-Path $f).Path)`\"\"\n"
             << "    } else {\n"
             << "        Write-Error \"sgv: file not found: $f\"\n"
             << "        exit 1\n"
             << "    }\n"
             << "}\n";
    ps1_file.close();
  }

  // If installed to custom directory (not WindowsApps), add to User PATH so it's globally available
  std::wstring parent_dir_str = std::filesystem::path(cli_path).parent_path().wstring();
  if (parent_dir_str.find(L"WindowsApps") == std::wstring::npos) {
    AddToUserPathIfMissing(parent_dir_str);
  }

  std::string cli_path_utf8 = Utf8FromUtf16(cli_path.c_str());
  res[flutter::EncodableValue("status")] = flutter::EncodableValue("success");
  res[flutter::EncodableValue("path")] = flutter::EncodableValue(cli_path_utf8);
  return res;
}

flutter::EncodableMap FlutterWindow::UninstallCli() {
  std::wstring cli_path = GetInstalledCliPath();
  RemoveCliFiles(cli_path);

  // Clean up both possible install locations and PATH registry
  PWSTR local_app_data = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local_app_data))) {
    std::wstring base_path(local_app_data);
    CoTaskMemFree(local_app_data);
    RemoveCliFiles(base_path + L"\\Microsoft\\WindowsApps\\sgv.cmd");
    RemoveCliFiles(base_path + L"\\SuperGoodViewer\\bin\\sgv.cmd");
    RemoveFromUserPathIfPresent(base_path + L"\\SuperGoodViewer\\bin");
  }

  flutter::EncodableMap res;
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

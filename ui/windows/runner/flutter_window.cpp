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
        } else if (call.method_name() == "setWindowTitle") {
          const auto* title = std::get_if<std::string>(call.arguments());
          if (title && this->GetHandle()) {
            std::wstring wide_title = Utf16FromUtf8(*title);
            ::SetWindowTextW(this->GetHandle(), wide_title.c_str());
          }
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

std::wstring GetEnvVar(const wchar_t* name) {
  DWORD required = ::GetEnvironmentVariableW(name, nullptr, 0);
  for (int attempt = 0; attempt < 3; ++attempt) {
    if (required == 0) {
      return L"";
    }
    std::wstring val(required, L'\0');
    DWORD written = ::GetEnvironmentVariableW(name, val.data(), required);
    if (written > 0 && written < required) {
      val.resize(written);
      return val;
    }
    if (written >= required) {
      // Buffer was too small because env var grew (TOCTOU); retry with new required size
      required = written;
      continue;
    }
    break;
  }
  return L"";
}

std::wstring GetCurrentExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH);
  while (true) {
    DWORD len = ::GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (len == 0) {
      return L"";
    }
    if (len < buffer.size()) {
      return std::wstring(buffer.data(), len);
    }
    // On buffer overflow / truncation, GetModuleFileNameW returns buffer.size()
    // Double buffer and retry.
    if (buffer.size() >= 32768) {
      return L"";
    }
    buffer.resize(buffer.size() * 2);
  }
}

std::wstring GetLocalAppDataPath() {
  PWSTR local_app_data = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local_app_data))) {
    std::wstring path(local_app_data);
    CoTaskMemFree(local_app_data);
    return path;
  }
  // Robust fallback 1: read %LOCALAPPDATA% dynamically without MAX_PATH buffer limitation
  std::wstring env_local = GetEnvVar(L"LOCALAPPDATA");
  if (!env_local.empty()) {
    return env_local;
  }
  // Robust fallback 2: check %USERPROFILE%\AppData\Local with non-throwing filesystem query
  std::wstring env_profile = GetEnvVar(L"USERPROFILE");
  if (!env_profile.empty()) {
    std::wstring p = env_profile + L"\\AppData\\Local";
    std::error_code ec;
    if (std::filesystem::is_directory(p, ec)) {
      return p;
    }
  }
  return L"";
}

struct CliLocations {
  std::wstring custom_dir;
  std::wstring custom_cmd;
  std::wstring winapps_dir;
  std::wstring winapps_cmd;

  static bool TryGet(CliLocations& out) {
    std::wstring base_path = GetLocalAppDataPath();
    if (base_path.empty()) return false;
    out.custom_dir = base_path + L"\\SuperGoodViewer\\bin";
    out.custom_cmd = out.custom_dir + L"\\sgv.cmd";
    out.winapps_dir = base_path + L"\\Microsoft\\WindowsApps";
    out.winapps_cmd = out.winapps_dir + L"\\sgv.cmd";
    return true;
  }
};

bool CanWriteToDir(const std::wstring& dir) {
  std::error_code ec;
  if (dir.empty() || !std::filesystem::exists(dir, ec)) return false;
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

std::wstring ResolveCliPath(const CliLocations& loc) {
  std::error_code ec;
  // 1. If already installed in either location, return the existing script path
  if (std::filesystem::exists(loc.custom_cmd, ec)) {
    return loc.custom_cmd;
  }
  if (std::filesystem::exists(loc.winapps_cmd, ec)) {
    return loc.winapps_cmd;
  }

  // 2. Not yet installed: prefer WindowsApps only if writable, otherwise use SuperGoodViewer\bin.
  // Pure query: do not create directories as a side effect.
  if (CanWriteToDir(loc.winapps_dir)) {
    return loc.winapps_cmd;
  }
  return loc.custom_cmd;
}

std::vector<std::wstring> GetPathSegments(const std::wstring& path_str) {
  std::vector<std::wstring> segments;
  size_t start = 0;
  while (start < path_str.size()) {
    size_t end = path_str.find(L';', start);
    if (end == std::wstring::npos) end = path_str.size();
    std::wstring segment = path_str.substr(start, end - start);
    if (!segment.empty()) {
      segments.push_back(segment);
    }
    start = end + 1;
  }
  return segments;
}

std::wstring NormalizeDirPath(const std::wstring& dir) {
  std::wstring s = dir;
  while (!s.empty() && (s.back() == L'\\' || s.back() == L'/')) s.pop_back();
  std::transform(s.begin(), s.end(), s.begin(), ::towlower);
  return s;
}

bool AreDirsEqual(const std::wstring& a, const std::wstring& b) {
  return NormalizeDirPath(a) == NormalizeDirPath(b);
}

bool ReadUserPath(std::wstring& out_path, DWORD& out_type) {
  HKEY hkey;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, L"Environment", 0, KEY_READ, &hkey) != ERROR_SUCCESS) {
    return false;
  }
  DWORD size = 0;
  DWORD type = 0;
  LONG status = ::RegQueryValueExW(hkey, L"Path", nullptr, &type, nullptr, &size);
  if (status == ERROR_FILE_NOT_FOUND) {
    ::RegCloseKey(hkey);
    out_path.clear();
    out_type = REG_EXPAND_SZ;
    return true; // Path value genuinely does not exist yet
  }
  if (status != ERROR_SUCCESS) {
    ::RegCloseKey(hkey);
    return false; // Failed to query registry key
  }
  if (size == 0) {
    ::RegCloseKey(hkey);
    out_path.clear();
    out_type = (type != 0 ? type : REG_EXPAND_SZ);
    return true; // Path exists and is empty
  }

  // Handle potential size-vs-data race or ERROR_MORE_DATA with retry loop
  for (int attempt = 0; attempt < 3; ++attempt) {
    std::vector<wchar_t> buffer(size / sizeof(wchar_t) + 2, 0);
    DWORD read_size = static_cast<DWORD>(buffer.size() * sizeof(wchar_t));
    status = ::RegQueryValueExW(hkey, L"Path", nullptr, &type, reinterpret_cast<LPBYTE>(buffer.data()), &read_size);
    if (status == ERROR_SUCCESS) {
      ::RegCloseKey(hkey);
      out_path = buffer.data();
      out_type = (type != 0 ? type : REG_EXPAND_SZ);
      return true;
    }
    if (status == ERROR_MORE_DATA) {
      size = read_size;
      continue;
    }
    break;
  }

  ::RegCloseKey(hkey);
  return false; // Second read failed; return false to avoid treating it as empty and clobbering user PATH
}

void WriteUserPathAndBroadcast(const std::wstring& new_path, DWORD type) {
  HKEY hkey;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, L"Environment", 0, KEY_WRITE, &hkey) == ERROR_SUCCESS) {
    ::RegSetValueExW(hkey, L"Path", 0, type ? type : REG_EXPAND_SZ,
                     reinterpret_cast<const BYTE*>(new_path.c_str()),
                     static_cast<DWORD>((new_path.size() + 1) * sizeof(wchar_t)));
    ::RegCloseKey(hkey);
    DWORD_PTR result;
    ::SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                          reinterpret_cast<LPARAM>(L"Environment"),
                          SMTO_ABORTIFHUNG, 3000, &result);
  }
}

void AddToUserPathIfMissing(const std::wstring& dir_to_add) {
  if (dir_to_add.empty()) return;
  std::wstring current_path;
  DWORD type = REG_EXPAND_SZ;
  if (!ReadUserPath(current_path, type)) {
    return; // Read failed; abort immediately to prevent clobbering user PATH
  }

  std::vector<std::wstring> segments = GetPathSegments(current_path);
  for (const auto& seg : segments) {
    if (AreDirsEqual(seg, dir_to_add)) {
      return;
    }
  }

  // Prepend to User PATH so this entry takes precedence over fallback locations (e.g. WindowsApps)
  std::wstring new_path = dir_to_add;
  if (!current_path.empty()) {
    if (new_path.back() != L';') {
      new_path += L';';
    }
    new_path += current_path;
  }
  WriteUserPathAndBroadcast(new_path, type);
}

void RemoveFromUserPathIfPresent(const std::wstring& dir_to_remove) {
  if (dir_to_remove.empty()) return;
  std::wstring current_path;
  DWORD type = REG_EXPAND_SZ;
  if (!ReadUserPath(current_path, type) || current_path.empty()) {
    return;
  }

  std::vector<std::wstring> segments = GetPathSegments(current_path);
  std::wstring new_path;
  bool changed = false;
  for (const auto& seg : segments) {
    if (AreDirsEqual(seg, dir_to_remove)) {
      changed = true;
    } else {
      if (!new_path.empty()) new_path += L';';
      new_path += seg;
    }
  }

  if (changed) {
    WriteUserPathAndBroadcast(new_path, type);
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
  CliLocations loc;
  if (!CliLocations::TryGet(loc)) return L"";
  return ResolveCliPath(loc);
}

flutter::EncodableMap FlutterWindow::CheckCliStatus() {
  std::wstring cli_path = GetInstalledCliPath();
  std::error_code ec;
  bool exists = !cli_path.empty() && std::filesystem::exists(cli_path, ec);

  std::wstring exe_path = GetCurrentExecutablePath();

  std::string path_utf8 = Utf8FromUtf16(cli_path.c_str());
  std::string target_utf8 = Utf8FromUtf16(exe_path.c_str());

  bool is_current_app = false;
  if (exists && !target_utf8.empty()) {
    std::ifstream file(cli_path);
    if (file.is_open()) {
      std::string content((std::istreambuf_iterator<char>(file)),
                          std::istreambuf_iterator<char>());
      // Exact check against target executable path, no loose fallback substring
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
  flutter::EncodableMap res;
  CliLocations loc;
  if (!CliLocations::TryGet(loc)) {
    res[flutter::EncodableValue("status")] = flutter::EncodableValue("error");
    res[flutter::EncodableValue("message")] = flutter::EncodableValue("无法定位本地应用数据目录");
    return res;
  }

  std::wstring cli_path = ResolveCliPath(loc);
  std::wstring initial_target = cli_path;

  std::wstring exe_path = GetCurrentExecutablePath();
  if (exe_path.empty()) {
    res[flutter::EncodableValue("status")] = flutter::EncodableValue("error");
    res[flutter::EncodableValue("message")] = flutter::EncodableValue("无法获取当前程序路径");
    return res;
  }
  std::string exe_utf8 = Utf8FromUtf16(exe_path.c_str());

  std::filesystem::path parent_dir = std::filesystem::path(cli_path).parent_path();
  std::error_code ec;
  std::filesystem::create_directories(parent_dir, ec);

  std::ofstream file(cli_path, std::ios::trunc);
  // Only attempt fallback if initial target was NOT already custom_dir (i.e. was WindowsApps and failed)
  if (!file.is_open() && !AreDirsEqual(parent_dir.wstring(), loc.custom_dir)) {
    cli_path = loc.custom_cmd;
    std::filesystem::create_directories(loc.custom_dir, ec);
    file.open(cli_path, std::ios::trunc);
    if (file.is_open()) {
      // Clean up stale script left at the old failed location (WindowsApps)
      RemoveCliFiles(initial_target);
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

  // Cross-location cleanup & PATH synchronization using loc directly
  std::wstring parent_dir_str = std::filesystem::path(cli_path).parent_path().wstring();
  if (AreDirsEqual(parent_dir_str, loc.custom_dir)) {
    // Installed to custom SuperGoodViewer\bin: register to PATH, clean any conflicting script in WindowsApps
    AddToUserPathIfMissing(parent_dir_str);
    RemoveCliFiles(loc.winapps_cmd);
  } else {
    // Installed to WindowsApps: clean any old script in SuperGoodViewer\bin, unregister from PATH
    RemoveCliFiles(loc.custom_cmd);
    RemoveFromUserPathIfPresent(loc.custom_dir);
  }

  std::string cli_path_utf8 = Utf8FromUtf16(cli_path.c_str());
  res[flutter::EncodableValue("status")] = flutter::EncodableValue("success");
  res[flutter::EncodableValue("path")] = flutter::EncodableValue(cli_path_utf8);
  return res;
}

flutter::EncodableMap FlutterWindow::UninstallCli() {
  flutter::EncodableMap res;
  CliLocations loc;
  if (!CliLocations::TryGet(loc)) {
    res[flutter::EncodableValue("status")] = flutter::EncodableValue("error");
    res[flutter::EncodableValue("message")] = flutter::EncodableValue("无法定位本地应用数据目录");
    return res;
  }

  RemoveCliFiles(loc.winapps_cmd);
  RemoveCliFiles(loc.custom_cmd);
  RemoveFromUserPathIfPresent(loc.custom_dir);

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

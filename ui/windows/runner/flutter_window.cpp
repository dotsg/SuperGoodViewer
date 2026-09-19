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
  // 1. Check existing .cmd scripts first (highest priority)
  if (std::filesystem::exists(loc.custom_cmd, ec)) return loc.custom_cmd;
  if (std::filesystem::exists(loc.winapps_cmd, ec)) return loc.winapps_cmd;

  // 2. Check existing .ps1 scripts second (fallback if .cmd is missing)
  if (std::filesystem::exists(loc.custom_dir + L"\\sgv.ps1", ec)) return loc.custom_cmd;
  if (std::filesystem::exists(loc.winapps_dir + L"\\sgv.ps1", ec)) return loc.winapps_cmd;

  // 3. Not yet installed: prefer WindowsApps only if writable, otherwise use SuperGoodViewer\bin.
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

bool ReadRegistryPath(HKEY root, const wchar_t* subkey, std::wstring& out_path, DWORD& out_type) {
  HKEY hkey;
  if (::RegOpenKeyExW(root, subkey, 0, KEY_READ, &hkey) != ERROR_SUCCESS) {
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
  return false;
}

bool ReadUserPath(std::wstring& out_path, DWORD& out_type) {
  return ReadRegistryPath(HKEY_CURRENT_USER, L"Environment", out_path, out_type);
}

bool ReadSystemPath(std::wstring& out_path, DWORD& out_type) {
  return ReadRegistryPath(HKEY_LOCAL_MACHINE, L"SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment", out_path, out_type);
}

bool WriteUserPathAndBroadcast(const std::wstring& new_path, DWORD type) {
  HKEY hkey;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, L"Environment", 0, KEY_WRITE, &hkey) != ERROR_SUCCESS) {
    return false;
  }
  LONG status = ::RegSetValueExW(hkey, L"Path", 0, type ? type : REG_EXPAND_SZ,
                                reinterpret_cast<const BYTE*>(new_path.c_str()),
                                static_cast<DWORD>((new_path.size() + 1) * sizeof(wchar_t)));
  ::RegCloseKey(hkey);
  if (status != ERROR_SUCCESS) {
    return false;
  }
  DWORD_PTR result;
  ::SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                        reinterpret_cast<LPARAM>(L"Environment"),
                        SMTO_ABORTIFHUNG, 3000, &result);
  return true;
}

bool IsDirInPath(const std::wstring& dir) {
  if (dir.empty()) return false;
  // 1. Check User PATH
  std::wstring user_path;
  DWORD type = REG_EXPAND_SZ;
  if (ReadUserPath(user_path, type) && !user_path.empty()) {
    for (const auto& seg : GetPathSegments(user_path)) {
      if (AreDirsEqual(seg, dir)) return true;
    }
  }
  // 2. Check System PATH
  std::wstring sys_path;
  if (ReadSystemPath(sys_path, type) && !sys_path.empty()) {
    for (const auto& seg : GetPathSegments(sys_path)) {
      if (AreDirsEqual(seg, dir)) return true;
    }
  }
  return false;
}

bool AddToUserPathIfMissing(const std::wstring& dir_to_add) {
  if (dir_to_add.empty()) return false;
  // If already active via System PATH, no need to add a duplicate to User PATH
  std::wstring sys_path;
  DWORD sys_type = REG_EXPAND_SZ;
  if (ReadSystemPath(sys_path, sys_type) && !sys_path.empty()) {
    for (const auto& seg : GetPathSegments(sys_path)) {
      if (AreDirsEqual(seg, dir_to_add)) {
        return true;
      }
    }
  }

  std::wstring current_path;
  DWORD type = REG_EXPAND_SZ;
  if (!ReadUserPath(current_path, type)) {
    return false; // Read failed; abort immediately to prevent clobbering user PATH
  }

  for (const auto& seg : GetPathSegments(current_path)) {
    if (AreDirsEqual(seg, dir_to_add)) {
      return true;
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
  return WriteUserPathAndBroadcast(new_path, type);
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

template <typename Writer>
bool WriteToFileAtomically(const std::wstring& target_path, Writer&& writer) {
  std::error_code ec;
  std::filesystem::path parent = std::filesystem::path(target_path).parent_path();
  if (!parent.empty()) {
    std::filesystem::create_directories(parent, ec);
  }
  std::wstring temp_path = target_path + L".tmp." + std::to_wstring(::GetCurrentProcessId());
  {
    std::ofstream out(temp_path, std::ios::trunc);
    if (!out.is_open()) {
      return false;
    }
    writer(out);
    out.close();
    if (out.fail()) {
      std::filesystem::remove(temp_path, ec);
      return false;
    }
  }

  DWORD orig_attrs = INVALID_FILE_ATTRIBUTES;
  if (std::filesystem::exists(target_path, ec)) {
    orig_attrs = ::GetFileAttributesW(target_path.c_str());
    if (orig_attrs != INVALID_FILE_ATTRIBUTES && (orig_attrs & FILE_ATTRIBUTE_READONLY)) {
      ::SetFileAttributesW(target_path.c_str(), orig_attrs & ~FILE_ATTRIBUTE_READONLY);
    }
  }

  if (!::MoveFileExW(temp_path.c_str(), target_path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED)) {
    if (orig_attrs != INVALID_FILE_ATTRIBUTES && (orig_attrs & FILE_ATTRIBUTE_READONLY)) {
      ::SetFileAttributesW(target_path.c_str(), orig_attrs);
    }
    std::filesystem::remove(temp_path, ec);
    return false;
  }
  return true;
}

void CleanOrphanedTempFiles(const std::wstring& dir) {
  if (dir.empty()) return;
  std::error_code dir_ec;
  if (!std::filesystem::is_directory(dir, dir_ec)) return;
  DWORD current_pid = ::GetCurrentProcessId();
  for (const auto& entry : std::filesystem::directory_iterator(dir, dir_ec)) {
    if (dir_ec) break;
    std::error_code file_ec;
    if (entry.is_regular_file(file_ec)) {
      std::wstring name = entry.path().filename().wstring();
      size_t prefix_len = 0;
      if (name.rfind(L"sgv.cmd.tmp.", 0) == 0) {
        prefix_len = 12;
      } else if (name.rfind(L"sgv.ps1.tmp.", 0) == 0) {
        prefix_len = 12;
      }
      if (prefix_len > 0) {
        std::wstring pid_part = name.substr(prefix_len);
        try {
          DWORD pid = std::stoul(pid_part);
          if (pid == current_pid) {
            continue;
          }
          HANDLE h_proc = ::OpenProcess(SYNCHRONIZE, FALSE, pid);
          if (h_proc != nullptr) {
            ::CloseHandle(h_proc);
            continue;
          }
        } catch (...) {
        }
        std::filesystem::remove(entry.path(), file_ec);
      }
    }
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
  std::filesystem::path p(cmd_path);
  CleanOrphanedTempFiles(p.parent_path().wstring());
}

}  // namespace

flutter::EncodableMap FlutterWindow::CheckCliStatus() {
  CliLocations loc;
  bool has_loc = CliLocations::TryGet(loc);
  std::wstring cli_path = has_loc ? ResolveCliPath(loc) : L"";
  std::error_code ec;
  bool cmd_exists = !cli_path.empty() && std::filesystem::exists(cli_path, ec);

  std::wstring ps1_path = L"";
  if (!cli_path.empty()) {
    auto dot_pos = cli_path.find_last_of(L'.');
    if (dot_pos != std::wstring::npos) {
      ps1_path = cli_path.substr(0, dot_pos) + L".ps1";
    }
  }
  bool ps1_exists = !ps1_path.empty() && std::filesystem::exists(ps1_path, ec);

  bool files_ok = cmd_exists && ps1_exists;
  bool any_file_exists = cmd_exists || ps1_exists;

  bool path_ok = true;
  if (has_loc && any_file_exists) {
    std::wstring parent_dir_str = std::filesystem::path(cli_path).parent_path().wstring();
    if (AreDirsEqual(parent_dir_str, loc.custom_dir)) {
      path_ok = IsDirInPath(loc.custom_dir);
    }
  }

  bool is_installed = files_ok && path_ok;
  bool is_partial = !is_installed && any_file_exists;

  std::string warning_utf8 = "";
  if (is_partial) {
    if (files_ok && !path_ok) {
      warning_utf8 = "安装不完整 (未添加到系统 PATH)";
    } else {
      warning_utf8 = "安装不完整 (部分工具未就绪)";
    }
  }

  std::wstring exe_path = GetCurrentExecutablePath();

  std::string path_utf8 = Utf8FromUtf16(cli_path.c_str());
  std::string target_utf8 = Utf8FromUtf16(exe_path.c_str());

  bool is_current_app = false;
  if (!target_utf8.empty()) {
    auto file_contains_target = [&](const std::wstring& p) {
      if (p.empty()) return false;
      std::ifstream file(p);
      if (!file.is_open()) return false;
      std::string content((std::istreambuf_iterator<char>(file)),
                          std::istreambuf_iterator<char>());
      return content.find(target_utf8) != std::string::npos;
    };

    if (cmd_exists && ps1_exists) {
      is_current_app = file_contains_target(cli_path) && file_contains_target(ps1_path);
    } else if (cmd_exists) {
      is_current_app = file_contains_target(cli_path);
    } else if (ps1_exists) {
      is_current_app = file_contains_target(ps1_path);
    }
  }

  flutter::EncodableMap res;
  res[flutter::EncodableValue("isInstalled")] = flutter::EncodableValue(is_installed);
  res[flutter::EncodableValue("isPartial")] = flutter::EncodableValue(is_partial);
  res[flutter::EncodableValue("path")] = flutter::EncodableValue(path_utf8);
  res[flutter::EncodableValue("target")] = flutter::EncodableValue(target_utf8);
  res[flutter::EncodableValue("isCurrentApp")] = flutter::EncodableValue(is_current_app);
  if (!warning_utf8.empty()) {
    res[flutter::EncodableValue("warning")] = flutter::EncodableValue(warning_utf8);
  }
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

  CleanOrphanedTempFiles(loc.winapps_dir);
  CleanOrphanedTempFiles(loc.custom_dir);

  std::wstring cli_path = ResolveCliPath(loc);
  std::wstring initial_target = cli_path;

  std::wstring exe_path = GetCurrentExecutablePath();
  if (exe_path.empty()) {
    res[flutter::EncodableValue("status")] = flutter::EncodableValue("error");
    res[flutter::EncodableValue("message")] = flutter::EncodableValue("无法获取当前程序路径");
    return res;
  }
  std::string exe_utf8 = Utf8FromUtf16(exe_path.c_str());
  std::wstring exe_dir = std::filesystem::path(exe_path).parent_path().wstring();
  std::string exe_dir_utf8 = Utf8FromUtf16(exe_dir.c_str());

  std::filesystem::path parent_dir = std::filesystem::path(cli_path).parent_path();
  std::error_code ec;
  std::filesystem::create_directories(parent_dir, ec);

  auto write_cmd = [&](std::ofstream& file) {
    // Write sgv.cmd with full export detection, version check, and CLI tool forwarding
    file << "@echo off\n"
         << "setlocal enabledelayedexpansion\n"
         << "set \"EXE_PATH=" << exe_utf8 << "\"\n"
         << "set \"EXE_DIR=" << exe_dir_utf8 << "\"\n"
         << "\n"
         << "rem 1. Resolve sgv-cli.exe location\n"
         << "set \"CLI_BIN=\"\n"
         << "if exist \"!EXE_DIR!\\sgv-cli.exe\" set \"CLI_BIN=!EXE_DIR!\\sgv-cli.exe\"\n"
         << "if not defined CLI_BIN (\n"
         << "    if exist \"%~dp0sgv-cli.exe\" set \"CLI_BIN=%~dp0sgv-cli.exe\"\n"
         << ")\n"
         << "if not defined CLI_BIN (\n"
         << "    if exist \"%~dp0..\\sgv-cli.exe\" set \"CLI_BIN=%~dp0..\\sgv-cli.exe\"\n"
         << ")\n"
         << "if not defined CLI_BIN (\n"
         << "    if exist \"%LOCALAPPDATA%\\SuperGoodViewer\\sgv-cli.exe\" set \"CLI_BIN=%LOCALAPPDATA%\\SuperGoodViewer\\sgv-cli.exe\"\n"
         << ")\n"
         << "if not defined CLI_BIN (\n"
         << "    if exist \"%LOCALAPPDATA%\\Programs\\SuperGoodViewer\\sgv-cli.exe\" set \"CLI_BIN=%LOCALAPPDATA%\\Programs\\SuperGoodViewer\\sgv-cli.exe\"\n"
         << ")\n"
         << "if not defined CLI_BIN (\n"
         << "    for %%X in (sgv-cli.exe) do (\n"
         << "        if not \"%%~$PATH:X\"==\"\" set \"CLI_BIN=%%~$PATH:X\"\n"
         << "    )\n"
         << ")\n"
         << "\n"
         << "rem 2. Handle help and version flags\n"
         << "if \"%~1\"==\"-h\" goto help\n"
         << "if \"%~1\"==\"--help\" goto help\n"
         << "if \"%~1\"==\"/?\" goto help\n"
         << "if \"%~1\"==\"-v\" goto version\n"
         << "if \"%~1\"==\"--version\" goto version\n"
         << "\n"
         << "rem 3. Check for export mode or flags\n"
         << "set \"IS_EXPORT=0\"\n"
         << "if /i \"%~1\"==\"export\" set \"IS_EXPORT=1\"\n"
         << "if \"!IS_EXPORT!\"==\"0\" call :check_export %*\n"
         << "\n"
         << "if \"!IS_EXPORT!\"==\"1\" (\n"
         << "    if not defined CLI_BIN (\n"
         << "        echo sgv: error: headless export tool 'sgv-cli.exe' not found >&2\n"
         << "        exit /b 1\n"
         << "    )\n"
         << "    \"!CLI_BIN!\" %*\n"
         << "    exit /b !ERRORLEVEL!\n"
         << ")\n"
         << "\n"
         << "rem 4. Open application or files\n"
         << "if \"%~1\"==\"\" (\n"
         << "    start \"\" \"!EXE_PATH!\"\n"
         << "    exit /b 0\n"
         << ")\n"
         << "\n"
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
         << "\n"
         << ":done\n"
         << "exit /b 0\n"
         << "\n"
         << ":version\n"
         << "if defined CLI_BIN (\n"
         << "    \"!CLI_BIN!\" --version\n"
         << "    exit /b !ERRORLEVEL!\n"
         << ")\n"
         << "echo SuperGoodViewer CLI Launcher\n"
         << "exit /b 0\n"
         << "\n"
         << ":help\n"
         << "chcp 65001 >nul 2>&1\n"
         << "echo SuperGoodViewer (超好读) CLI Launcher ^& Tool\n"
         << "echo.\n"
         << "echo Usage:\n"
         << "echo   sgv [file.md ...]               Open markdown file(s) in SuperGoodViewer GUI\n"
         << "echo   sgv export ^<path^>... [options]  Export markdown file(s) or directory to PDF\n"
         << "echo   sgv ^<file.md^> -o ^<output.pdf^>   Export single markdown file to PDF\n"
         << "echo   sgv                             Launch or focus SuperGoodViewer GUI\n"
         << "echo   sgv -h, --help                  Show this help message\n"
         << "echo.\n"
         << "echo Export Options:\n"
         << "echo   -o, --output ^<path^>             Output PDF path or destination directory\n"
         << "echo   -f, --format ^<format^>           Page layout format: a4, a4-landscape, fluid, slide, slide-4-3\n"
         << "echo       --fluid                     Shorthand for --format fluid\n"
         << "echo   -t, --theme ^<theme^>             Theme: light, dark (default: light)\n"
         << "echo       --dark                      Shorthand for --theme dark\n"
         << "echo   -s, --font-size ^<pt^>            Font size in points (default: 10.5)\n"
         << "echo   -r, --recursive                 Recursively scan subdirectories (default: enabled)\n"
         << "echo       --no-recursive              Do not scan subdirectories\n"
         << "echo.\n"
         << "echo Examples:\n"
         << "echo   sgv README.md                             # View in GUI\n"
         << "echo   sgv export README.md                      # Export to README.pdf\n"
         << "echo   sgv export .\\docs -o .\\dist               # Batch export .\\docs to .\\dist\n"
         << "echo   type draft.md ^| sgv export - -o draft.pdf  # Export from stdin\n"
         << "exit /b 0\n"
         << "\n"
         << ":check_export\n"
         << "if \"%~1\"==\"\" goto :eof\n"
         << "if /i \"%~1\"==\"-o\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"--output\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"--export\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"-f\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"--format\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"--page-format\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"--fluid\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"-t\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"--theme\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"--dark\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"-s\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"--font-size\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"--title\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"-r\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"--recursive\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"--no-recursive\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "if /i \"%~1\"==\"--image-cache-dir\" (set \"IS_EXPORT=1\" & goto :eof)\n"
         << "shift\n"
         << "goto check_export\n";
  };

  bool cmd_written = WriteToFileAtomically(cli_path, write_cmd);
  // Only attempt fallback if initial target was NOT already custom_dir (i.e. was WindowsApps and failed)
  if (!cmd_written && !AreDirsEqual(parent_dir.wstring(), loc.custom_dir)) {
    cli_path = loc.custom_cmd;
    cmd_written = WriteToFileAtomically(cli_path, write_cmd);
    if (cmd_written) {
      // Clean up stale script left at the old failed location (WindowsApps)
      RemoveCliFiles(initial_target);
    }
  }

  if (!cmd_written) {
    res[flutter::EncodableValue("status")] = flutter::EncodableValue("error");
    res[flutter::EncodableValue("message")] = flutter::EncodableValue("写入 sgv.cmd 脚本失败");
    return res;
  }

  // Also write sgv.ps1
  std::wstring ps1_path = cli_path.substr(0, cli_path.find_last_of(L'.')) + L".ps1";
  auto write_ps1 = [&](std::ofstream& ps1_file) {
    ps1_file << "\xEF\xBB\xBF";
    ps1_file << "$exePath = '" << exe_utf8 << "'\n"
             << "$exeDir = '" << exe_dir_utf8 << "'\n"
             << "\n"
             << "# 1. Locate sgv-cli executable\n"
             << "$cliBin = $null\n"
             << "$cliCandidates = @(\n"
             << "    \"$exeDir\\sgv-cli.exe\",\n"
             << "    \"$PSScriptRoot\\sgv-cli.exe\",\n"
             << "    \"$PSScriptRoot\\..\\sgv-cli.exe\",\n"
             << "    \"$env:LOCALAPPDATA\\SuperGoodViewer\\sgv-cli.exe\",\n"
             << "    \"$env:LOCALAPPDATA\\Programs\\SuperGoodViewer\\sgv-cli.exe\"\n"
             << ")\n"
             << "foreach ($c in $cliCandidates) {\n"
             << "    if (Test-Path $c) { $cliBin = (Resolve-Path $c).Path; break }\n"
             << "}\n"
             << "if (-not $cliBin) {\n"
             << "    $cmd = Get-Command 'sgv-cli.exe' -ErrorAction SilentlyContinue\n"
             << "    if ($cmd) { $cliBin = $cmd.Source }\n"
             << "}\n"
             << "\n"
             << "if ($args.Count -eq 1 -and ($args[0] -in @('-v', '--version', '-version', '/v'))) {\n"
             << "    if ($cliBin) { & $cliBin --version; exit $LASTEXITCODE }\n"
             << "    Write-Host 'SuperGoodViewer CLI Launcher'\n"
             << "    exit 0\n"
             << "}\n"
             << "\n"
             << "if ($args.Count -eq 1 -and ($args[0] -in @('-h', '--help', '-help', '-?', '/?'))) {\n"
             << "    Write-Host 'SuperGoodViewer (超好读) CLI Launcher & Tool'\n"
             << "    Write-Host ''\n"
             << "    Write-Host 'Usage:'\n"
             << "    Write-Host '  sgv [file.md ...]               Open markdown file(s) in SuperGoodViewer GUI'\n"
             << "    Write-Host '  sgv export <path>... [options]  Export markdown file(s) or directory to PDF'\n"
             << "    Write-Host '  sgv <file.md> -o <output.pdf>   Export single markdown file to PDF'\n"
             << "    Write-Host '  sgv                             Launch or focus SuperGoodViewer GUI'\n"
             << "    Write-Host '  sgv -h, --help                  Show this help message'\n"
             << "    Write-Host ''\n"
             << "    Write-Host 'Export Options:'\n"
             << "    Write-Host '  -o, --output <path>             Output PDF path or destination directory'\n"
             << "    Write-Host '  -f, --format <format>           Page layout format: a4, a4-landscape, fluid, slide, slide-4-3'\n"
             << "    Write-Host '      --fluid                     Shorthand for --format fluid'\n"
             << "    Write-Host '  -t, --theme <theme>             Theme: light, dark (default: light)'\n"
             << "    Write-Host '      --dark                      Shorthand for --theme dark'\n"
             << "    Write-Host '  -s, --font-size <pt>            Font size in points (default: 10.5)'\n"
             << "    Write-Host '  -r, --recursive                 Recursively scan subdirectories (default: enabled)'\n"
             << "    Write-Host '      --no-recursive              Do not scan subdirectories'\n"
             << "    Write-Host ''\n"
             << "    Write-Host 'Examples:'\n"
             << "    Write-Host '  sgv README.md                             # View in GUI'\n"
             << "    Write-Host '  sgv export README.md                      # Export to README.pdf'\n"
             << "    Write-Host '  sgv export .\\docs -o .\\dist               # Batch export .\\docs to .\\dist'\n"
             << "    Write-Host '  type draft.md | sgv export - -o draft.pdf  # Export from stdin'\n"
             << "    exit 0\n"
             << "}\n"
             << "\n"
             << "# 2. Check for export mode\n"
             << "$isExport = $false\n"
             << "if ($args.Count -gt 0 -and $args[0] -eq 'export') {\n"
             << "    $isExport = $true\n"
             << "} else {\n"
             << "    foreach ($f in $args) {\n"
             << "        if ($f -in @('-o', '--output', '--export', '-f', '--format', '--page-format', '--fluid', '-t', '--theme', '--dark', '-s', '--font-size', '--title', '-r', '--recursive', '--no-recursive', '--image-cache-dir')) {\n"
             << "            $isExport = $true\n"
             << "            break\n"
             << "        }\n"
             << "    }\n"
             << "}\n"
             << "\n"
             << "if ($isExport) {\n"
             << "    if (-not $cliBin -or -not (Test-Path $cliBin)) {\n"
             << "        Write-Error 'sgv: error: headless export tool sgv-cli.exe not found'\n"
             << "        exit 1\n"
             << "    }\n"
             << "    & $cliBin @args\n"
             << "    exit $LASTEXITCODE\n"
             << "}\n"
             << "\n"
             << "# 3. Launch GUI\n"
             << "if ($args.Count -eq 0) {\n"
             << "    Start-Process -FilePath $exePath\n"
             << "    exit 0\n"
             << "}\n"
             << "foreach ($f in $args) {\n"
             << "    if (Test-Path -LiteralPath $f) {\n"
             << "        $absPath = (Resolve-Path -LiteralPath $f).Path\n"
             << "        Start-Process -FilePath $exePath -ArgumentList \"`\"$absPath`\"\"\n"
             << "    } else {\n"
             << "        Write-Error \"sgv: error: file not found: $f\"\n"
             << "        exit 1\n"
             << "    }\n"
             << "}\n";
  };

  bool ps1_written = WriteToFileAtomically(ps1_path, write_ps1);
  bool ps1_exists_now = std::filesystem::exists(ps1_path, ec);

  // Cross-location cleanup & PATH synchronization using loc directly
  bool path_ok = true;
  std::wstring parent_dir_str = std::filesystem::path(cli_path).parent_path().wstring();
  if (AreDirsEqual(parent_dir_str, loc.custom_dir)) {
    // Installed to custom SuperGoodViewer\bin: register to PATH, clean any conflicting script in WindowsApps
    path_ok = AddToUserPathIfMissing(parent_dir_str);
    RemoveCliFiles(loc.winapps_cmd);
  } else {
    // Installed to WindowsApps: clean any old script in SuperGoodViewer\bin, unregister from PATH
    RemoveCliFiles(loc.custom_cmd);
    RemoveFromUserPathIfPresent(loc.custom_dir);
  }

  std::string cli_path_utf8 = Utf8FromUtf16(cli_path.c_str());
  res[flutter::EncodableValue("status")] = flutter::EncodableValue("success");
  res[flutter::EncodableValue("path")] = flutter::EncodableValue(cli_path_utf8);
  std::vector<std::string> warnings;
  if (!path_ok) {
    warnings.push_back("未能将安装目录添加到环境变量 PATH（注册表受限），命令行可能无法直接调用");
  }
  if (!ps1_written) {
    warnings.push_back(
        ps1_exists_now
            ? "sgv.ps1 未能更新（可能被占用），PowerShell 下可能仍指向旧版本"
            : "未能创建 sgv.ps1 脚本");
  }

  if (!warnings.empty()) {
    std::string combined_warning;
    if (warnings.size() == 1) {
      if (!path_ok) {
        combined_warning = "脚本已生成，但未能将安装目录添加到用户环境变量 PATH（注册表受限），命令行可能无法直接调用";
      } else {
        combined_warning = ps1_exists_now
            ? "sgv.cmd 安装成功，但 sgv.ps1 未能更新（可能被占用），PowerShell 下可能仍指向旧版本"
            : "sgv.cmd 安装成功，但未能创建 sgv.ps1 脚本";
      }
    } else {
      combined_warning = "脚本已生成，但未能添加到环境变量 PATH（注册表受限）；且 " +
          std::string(ps1_exists_now
              ? "sgv.ps1 未能更新（可能被占用），PowerShell 下可能仍指向旧版本"
              : "未能创建 sgv.ps1 脚本");
    }
    res[flutter::EncodableValue("warning")] = flutter::EncodableValue(combined_warning);
  }
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

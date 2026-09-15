#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shlobj.h>
#include <fstream>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

std::wstring GetInitialAppTitle() {
  PWSTR app_data = nullptr;
  if (SUCCEEDED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &app_data))) {
    std::wstring pref_path = std::wstring(app_data) + L"\\com.sogood.sogoodviewer\\preferences.json";
    ::CoTaskMemFree(app_data);
    std::ifstream file(pref_path);
    if (file.is_open()) {
      std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
      file.close();
      if (content.find("\"language\": \"en\"") != std::string::npos ||
          content.find("\"language\":\"en\"") != std::string::npos) {
        return L"SuperGoodViewer";
      }
      if (content.find("\"language\": \"zhHant\"") != std::string::npos ||
          content.find("\"language\":\"zhHant\"") != std::string::npos) {
        return L"\u8D85\u597D\u8B80";
      }
    }
  }
  return L"\u8D85\u597D\u8BFB";
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Single-instance enforcement: if an instance is already running, forward
  // any command-line file payload to the running window via WM_COPYDATA and exit.
  constexpr const wchar_t kMutexName[] = L"SuperGoodViewer_SingleInstance_Mutex";
  const std::wstring app_window_title = GetInitialAppTitle();

  HANDLE mutex = ::CreateMutex(nullptr, TRUE, kMutexName);
  bool already_running = (::GetLastError() == ERROR_ALREADY_EXISTS);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  if (already_running) {
    HWND existing_hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
    if (!existing_hwnd) {
      existing_hwnd = ::FindWindow(nullptr, app_window_title.c_str());
    }
    if (existing_hwnd) {
      for (size_t i = 0; i < command_line_arguments.size(); ++i) {
        const auto& arg = command_line_arguments[i];
        if (!arg.empty() && arg[0] != '-' && arg != "--args") {
          COPYDATASTRUCT cds;
          cds.dwData = 0x53475631; // 'SGV1'
          cds.cbData = static_cast<DWORD>(arg.size() + 1);
          cds.lpData = const_cast<char*>(arg.c_str());
          ::SendMessage(existing_hwnd, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds));
        }
      }
      ::SetForegroundWindow(existing_hwnd);
      if (::IsIconic(existing_hwnd)) {
        ::ShowWindow(existing_hwnd, SW_RESTORE);
      }
    }
    if (mutex) {
      ::CloseHandle(mutex);
    }
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(app_window_title, origin, size)) {
    if (mutex) ::CloseHandle(mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (mutex) {
    ::CloseHandle(mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}

#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that hosts a Flutter view and provides native desktop integration.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Handle external file opening requests (e.g. from WM_COPYDATA or second process)
  void HandleOpenFile(const std::string& path);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetupMethodChannels();
  bool ToggleFullScreen();
  void StartDragging();
  void Zoom();

  // CLI tools management on Windows
  flutter::EncodableMap CheckCliStatus();
  flutter::EncodableMap InstallCli();
  flutter::EncodableMap UninstallCli();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // MethodChannels for window and app integration
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> app_channel_;

  // Fullscreen state tracking
  bool is_full_screen_ = false;
  WINDOWPLACEMENT saved_placement_ = { sizeof(WINDOWPLACEMENT) };
  DWORD saved_style_ = 0;
  DWORD saved_ex_style_ = 0;

  // Pending file to open if channel is not ready yet
  std::string pending_file_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Set a svid:// URI to send to Flutter after first frame.
  void SetLaunchUri(const std::string& uri);

  // Send a svid:// URI to Flutter via MethodChannel.
  void SendUri(const std::string& uri);

  // Send a Windows power event (suspend/resume) to Flutter via MethodChannel.
  void SendPowerEvent(const std::string& event);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Receives Flutter theme updates so the native fallback background matches.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      backdrop_theme_channel_;

  // Lets Dart read/re-apply the brand AUMID compiled into the Windows runner
  // before and after plugins that touch WinToast or shell shortcuts initialize.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      stable_windows_identity_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      windows_identity_channel_;

  // URI to forward to Flutter after first frame.
  std::string pending_uri_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

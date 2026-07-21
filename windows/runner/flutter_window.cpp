#include "flutter_window.h"

#include <limits>
#include <optional>
#include <string>
#include <utility>
#include <variant>

#include <windows.h>
#include <shellapi.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <shobjidl.h>

#include "brand_config.h"
#include "clipboard_monitor_plugin.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "floating_capture_panel_plugin.h"
#include "flutter/generated_plugin_registrant.h"

// Phase 2D.3 (anh Quân Windows freeze 2026-05-12): popup engine spawned by
// desktop_multi_window must NOT pull in the full RegisterPlugins() list.
// Registering all 16 plugins (MediaKit, WebView2, sqlite3, sentry, tray,
// hotkey, etc.) synchronously on the main thread during popup spawn
// blocks the main app UI for 100ms-multi-seconds. The popup engine only
// uses 3 plugins (desktop_multi_window for IPC is auto-registered by the
// plugin internally; we add screen_retriever, window_manager, and our
// own FloatingCapturePanelPlugin).
#include "screen_retriever/screen_retriever_plugin.h"
#include "window_manager/window_manager_plugin.h"

namespace {

constexpr char kStableWindowsIdentityChannel[] = "snakeloader/windows_identity";

bool IsValidUtf8(const std::string& value) {
  if (value.empty() ||
      value.size() > static_cast<size_t>(std::numeric_limits<int>::max())) {
    return false;
  }

  return ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                               static_cast<int>(value.size()), nullptr, 0) > 0;
}

std::string WideToUtf8(const wchar_t* value) {
  if (value == nullptr || value[0] == L'\0') {
    return std::string();
  }

  const int size = ::WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0,
                                        nullptr, nullptr);
  if (size <= 1) {
    return std::string();
  }

  std::string result(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), size, nullptr,
                        nullptr);
  result.pop_back();
  return result;
}

void HandleWindowsIdentityMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "getAppUserModelId") {
    result->Success(
        flutter::EncodableValue(WideToUtf8(BRAND_APP_USER_MODEL_ID)));
    return;
  }

  if (call.method_name() != "applyAppUserModelId") {
    result->NotImplemented();
    return;
  }

  const HRESULT hr =
      ::SetCurrentProcessExplicitAppUserModelID(BRAND_APP_USER_MODEL_ID);
  if (FAILED(hr)) {
    result->Error("aumid_apply_failed",
                  "SetCurrentProcessExplicitAppUserModelID failed.");
    return;
  }

  result->Success();
}

}  // namespace

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

  // V2 home: backdrop theme channel — Dart pushes theme changes so native
  // window backdrop matches the app theme (avoids white flash on Windows
  // dark theme). See lib/core/services/windows_backdrop_service.dart.
  backdrop_theme_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          BRAND_BUNDLE_ID "/theme_events",
          &flutter::StandardMethodCodec::GetInstance());
  backdrop_theme_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "setBackdropTheme") {
          result->NotImplemented();
          return;
        }

        const auto* theme = std::get_if<std::string>(call.arguments());
        if (theme == nullptr || (*theme != "dark" && *theme != "light")) {
          result->Error("invalid_theme",
                        "Expected backdrop theme to be 'dark' or 'light'.");
          return;
        }

        SetBackdropTheme(*theme == "dark");
        result->Success();
      });

  // Windows shell identity channels. The stable channel lets Dart read the
  // AUMID compiled into this exe before notification setup, so a Dart/native
  // brand mismatch cannot make WinToast emit under the wrong identity. Keep the
  // branded channel for existing brand-scoped callers.
  stable_windows_identity_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          kStableWindowsIdentityChannel,
          &flutter::StandardMethodCodec::GetInstance());
  stable_windows_identity_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        HandleWindowsIdentityMethodCall(call, std::move(result));
      });

  windows_identity_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          BRAND_BUNDLE_ID "/windows_identity",
          &flutter::StandardMethodCodec::GetInstance());
  windows_identity_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        HandleWindowsIdentityMethodCall(call, std::move(result));
      });

  // Register native clipboard monitor for v2.1 floating capture feature.
  // Event-driven via AddClipboardFormatListener (no polling). See
  // windows/runner/clipboard_monitor_plugin.cpp.
  // PluginRegistrarManager owns the wrapped registrar so it outlives
  // registration even though `this` scope ends.
  ClipboardMonitorPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(
              flutter_controller_->engine()->GetRegistrarForPlugin(
                  "ClipboardMonitorPlugin")));

  // v2.1 floating capture: register the minimal plugin set that the
  // popup engine actually uses. DO NOT call RegisterPlugins() — that
  // pulls in 16 plugins (MediaKit, WebView2, sqlite3, sentry, ...)
  // synchronously on main thread during popup spawn, which was the
  // primary cause of the Windows main-app freeze + relaunch loop
  // observed 2026-05-12 (vidcombo_2026-05-12.log: 11 cold-starts in
  // 8 minutes).
  //
  // Plugins the popup engine needs:
  //   - DesktopMultiWindowPlugin: registered automatically by the plugin
  //     itself (multi_window_manager.cpp:75) — do NOT add here.
  //   - ScreenRetrieverPlugin: primary display + bounds (position store).
  //   - WindowManagerPlugin: show/hide/setSize/setPosition.
  //   - FloatingCapturePanelPlugin (Phase 1C.1): WS_EX_NOACTIVATE +
  //     HWND_TOPMOST attribute application.
  //
  // Plugins we deliberately OMIT (heavy native init, popup doesn't use):
  //   media_kit_libs_windows_video, media_kit_video, sqlite3_flutter_libs,
  //   flutter_inappwebview_windows, sentry_flutter, tray_manager,
  //   hotkey_manager_windows, local_notifier, connectivity_plus,
  //   desktop_drop, volume_controller, url_launcher_windows,
  //   flutter_secure_storage_windows.
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();

    ScreenRetrieverPluginRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("ScreenRetrieverPlugin"));
    WindowManagerPluginRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("WindowManagerPlugin"));

    FloatingCapturePanelPlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarManager::GetInstance()
            ->GetRegistrar<flutter::PluginRegistrarWindows>(
                registry->GetRegistrarForPlugin(
                    "FloatingCapturePanelPlugin")));
  });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
    // Forward launch URI to Flutter after first frame (MethodChannel is ready)
    if (!pending_uri_.empty()) {
      // Small delay to ensure Dart-side handler is registered
      ::SetTimer(GetHandle(), 42, 300, nullptr);
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetLaunchUri(const std::string& uri) {
  pending_uri_ = uri;
}

void FlutterWindow::SendUri(const std::string& uri) {
  if (!flutter_controller_ || !flutter_controller_->engine()) return;
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      BRAND_BUNDLE_ID "/uri_scheme",
      &flutter::StandardMethodCodec::GetInstance());
  channel->InvokeMethod("handleUri",
      std::make_unique<flutter::EncodableValue>(uri));
}

void FlutterWindow::SendPowerEvent(const std::string& event) {
  if (!flutter_controller_ || !flutter_controller_->engine()) return;
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      BRAND_BUNDLE_ID "/power_events",
      &flutter::StandardMethodCodec::GetInstance());
  channel->InvokeMethod("handlePowerEvent",
      std::make_unique<flutter::EncodableValue>(event));
}

void FlutterWindow::OnDestroy() {
  backdrop_theme_channel_ = nullptr;
  stable_windows_identity_channel_ = nullptr;
  windows_identity_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
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
    case WM_COPYDATA: {
      auto copy_data = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (copy_data != nullptr && copy_data->lpData != nullptr &&
          copy_data->dwData == 1 && copy_data->cbData >= 2) {
        const auto* data = static_cast<const char*>(copy_data->lpData);
        const size_t byte_count = static_cast<size_t>(copy_data->cbData);
        if (data[byte_count - 1] == '\0') {
          std::string uri(data, byte_count - 1);
          if (uri.find('\0') == std::string::npos && IsValidUtf8(uri) &&
              uri.rfind(BRAND_URL_SCHEME, 0) == 0) {
            SendUri(uri);
            ::ShowWindow(hwnd, SW_SHOW);
            if (::IsIconic(hwnd)) {
              ::ShowWindow(hwnd, SW_RESTORE);
            }
            ::SetForegroundWindow(hwnd);
            return TRUE;
          }
        }
      }
      return FALSE;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_TIMER:
      if (wparam == 42 && !pending_uri_.empty()) {
        ::KillTimer(hwnd, 42);
        SendUri(pending_uri_);
        pending_uri_.clear();
      }
      break;
    case WM_POWERBROADCAST:
      if (wparam == PBT_APMSUSPEND) {
        SendPowerEvent("suspend");
        return TRUE;
      } else if (wparam == PBT_APMRESUMEAUTOMATIC ||
                 wparam == PBT_APMRESUMESUSPEND) {
        SendPowerEvent("resume");
        return TRUE;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

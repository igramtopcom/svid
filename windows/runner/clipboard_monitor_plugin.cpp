#include "clipboard_monitor_plugin.h"

#include <windows.h>

#include <iostream>
#include <optional>

namespace {

// Class name for the hidden message-only window. Per-instance class would
// require generated names; a single class is fine because we instantiate the
// plugin once per Flutter engine and the WindowProc dispatches through the
// HWND user-data slot.
constexpr wchar_t kWindowClassName[] = L"SvidClipboardMonitorWindow";

// Convert a UTF-16 wide string to UTF-8 std::string. Returns empty string on
// conversion failure or zero-length input.
std::string Utf16ToUtf8(const std::wstring& utf16) {
  if (utf16.empty()) return std::string();
  int bytes = WideCharToMultiByte(CP_UTF8, 0, utf16.data(),
                                  static_cast<int>(utf16.size()), nullptr, 0,
                                  nullptr, nullptr);
  if (bytes <= 0) return std::string();
  std::string utf8(static_cast<size_t>(bytes), 0);
  WideCharToMultiByte(CP_UTF8, 0, utf16.data(),
                      static_cast<int>(utf16.size()), utf8.data(), bytes,
                      nullptr, nullptr);
  return utf8;
}

}  // namespace

// static
void ClipboardMonitorPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<ClipboardMonitorPlugin>();
  auto* plugin_ptr = plugin.get();

  plugin->method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "svid.clipboard_monitor/methods",
          &flutter::StandardMethodCodec::GetInstance());
  plugin->method_channel_->SetMethodCallHandler(
      [plugin_ptr](const auto& call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  plugin->event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "svid.clipboard_monitor/events",
          &flutter::StandardMethodCodec::GetInstance());
  auto stream_handler =
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [plugin_ptr](
              const flutter::EncodableValue* arguments,
              std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                  events) { return plugin_ptr->OnListen(arguments, std::move(events)); },
          [plugin_ptr](const flutter::EncodableValue* arguments) {
            return plugin_ptr->OnCancel(arguments);
          });
  plugin->event_channel_->SetStreamHandler(std::move(stream_handler));

  registrar->AddPlugin(std::move(plugin));
}

ClipboardMonitorPlugin::ClipboardMonitorPlugin() = default;

ClipboardMonitorPlugin::~ClipboardMonitorPlugin() {
  // Defensive: ensure listener is removed and window is destroyed even if
  // Dart never calls stop().
  StopMonitoring();
}

void ClipboardMonitorPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "start") {
    // intervalMs is intentionally ignored on Windows — AddClipboardFormatListener
    // is event-driven, no polling occurs.
    bool ok = StartMonitoring();
    if (ok) {
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Error("CLIPBOARD_START_FAILED",
                    "AddClipboardFormatListener returned false");
    }
  } else if (method == "stop") {
    StopMonitoring();
    result->Success(flutter::EncodableValue(true));
  } else if (method == "readText") {
    auto text = ReadClipboardText();
    if (text.has_value()) {
      result->Success(flutter::EncodableValue(text.value()));
    } else {
      result->Success(flutter::EncodableValue());  // null
    }
  } else {
    result->NotImplemented();
  }
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
ClipboardMonitorPlugin::OnListen(
    const flutter::EncodableValue* /*arguments*/,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
  event_sink_ = std::move(events);
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
ClipboardMonitorPlugin::OnCancel(const flutter::EncodableValue* /*arguments*/) {
  event_sink_.reset();
  return nullptr;
}

bool ClipboardMonitorPlugin::StartMonitoring() {
  if (message_window_ != nullptr) {
    // Already started — idempotent (Dart side also guards but defense-in-depth).
    return true;
  }

  // Register the window class once per process (RegisterClassEx returns 0 on
  // duplicate registration, but GetLastError == ERROR_CLASS_ALREADY_EXISTS is
  // benign). Cache check via GetClassInfoEx.
  HINSTANCE hinst = GetModuleHandle(nullptr);
  WNDCLASSEX existing = {};
  if (!GetClassInfoEx(hinst, kWindowClassName, &existing)) {
    WNDCLASSEX wc = {};
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.lpfnWndProc = &ClipboardMonitorPlugin::WindowProc;
    wc.hInstance = hinst;
    wc.lpszClassName = kWindowClassName;
    if (RegisterClassEx(&wc) == 0) {
      DWORD err = GetLastError();
      if (err != ERROR_CLASS_ALREADY_EXISTS) {
        std::cerr << "[ClipboardMonitor] RegisterClassEx failed: " << err
                  << std::endl;
        return false;
      }
    }
  }

  // Create a hidden message-only window. HWND_MESSAGE parent means it never
  // appears on screen, in the taskbar, or in Alt+Tab; it only exists to
  // receive Windows messages.
  message_window_ = CreateWindowEx(
      0, kWindowClassName, L"Svid Clipboard Monitor", 0, 0, 0, 0, 0,
      HWND_MESSAGE, nullptr, hinst, this);
  if (message_window_ == nullptr) {
    std::cerr << "[ClipboardMonitor] CreateWindowEx failed: " << GetLastError()
              << std::endl;
    return false;
  }

  // Stash `this` in the window's user-data slot so WindowProc can dispatch.
  SetWindowLongPtr(message_window_, GWLP_USERDATA,
                   reinterpret_cast<LONG_PTR>(this));

  if (!AddClipboardFormatListener(message_window_)) {
    std::cerr << "[ClipboardMonitor] AddClipboardFormatListener failed: "
              << GetLastError() << std::endl;
    DestroyWindow(message_window_);
    message_window_ = nullptr;
    return false;
  }
  format_listener_active_ = true;
  return true;
}

void ClipboardMonitorPlugin::StopMonitoring() {
  if (message_window_ == nullptr) {
    return;
  }
  if (format_listener_active_) {
    RemoveClipboardFormatListener(message_window_);
    format_listener_active_ = false;
  }
  DestroyWindow(message_window_);
  message_window_ = nullptr;
}

std::optional<std::string> ClipboardMonitorPlugin::ReadClipboardText() {
  // hwnd argument is the new clipboard owner — passing the message window is
  // benign and avoids needing the main FlutterWindow's HWND.
  if (!OpenClipboard(message_window_)) {
    return std::nullopt;
  }

  std::optional<std::string> result;

  // CF_UNICODETEXT is the canonical text format — Windows auto-synthesizes it
  // from CF_TEXT/CF_OEMTEXT if needed.
  HANDLE handle = GetClipboardData(CF_UNICODETEXT);
  if (handle != nullptr) {
    auto* utf16_data = static_cast<const wchar_t*>(GlobalLock(handle));
    if (utf16_data != nullptr) {
      std::wstring utf16(utf16_data);
      GlobalUnlock(handle);
      std::string utf8 = Utf16ToUtf8(utf16);
      if (!utf8.empty()) {
        result = std::move(utf8);
      }
    }
  }

  CloseClipboard();
  return result;
}

void ClipboardMonitorPlugin::OnClipboardUpdate() {
  if (!event_sink_) {
    // No listener attached yet — silently drop. Dart side's
    // NativeClipboardSource subscribes BEFORE invoking start, so this branch
    // is only hit when the engine is shutting down.
    return;
  }
  auto text = ReadClipboardText();
  if (text.has_value()) {
    event_sink_->Success(flutter::EncodableValue(text.value()));
  }
  // else: non-text clipboard (image/file/HTML) — silently filtered per spec
  // §11 E20.
}

// static
LRESULT CALLBACK ClipboardMonitorPlugin::WindowProc(HWND hwnd, UINT msg,
                                                    WPARAM wparam,
                                                    LPARAM lparam) {
  if (msg == WM_CLIPBOARDUPDATE) {
    auto* self = reinterpret_cast<ClipboardMonitorPlugin*>(
        GetWindowLongPtr(hwnd, GWLP_USERDATA));
    if (self != nullptr) {
      self->OnClipboardUpdate();
    }
    return 0;
  }
  return DefWindowProc(hwnd, msg, wparam, lparam);
}

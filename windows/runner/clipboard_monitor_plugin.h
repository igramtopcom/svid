#ifndef RUNNER_CLIPBOARD_MONITOR_PLUGIN_H_
#define RUNNER_CLIPBOARD_MONITOR_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <string>

// SSvid v2.1 floating capture — Windows clipboard monitor.
//
// Uses Win32 AddClipboardFormatListener API (event-driven, NOT polling).
// A hidden message-only window (HWND_MESSAGE parent) receives
// WM_CLIPBOARDUPDATE messages whenever the system clipboard changes.
// On change we read CF_UNICODETEXT and emit via FlutterEventSink — no
// polling cost at all.
//
// Channels (mirror macOS plugin so the Dart NativeClipboardSource works
// unchanged across platforms):
//   - Method: ssvid.clipboard_monitor/methods (start/stop/readText)
//   - Event:  ssvid.clipboard_monitor/events (clipboard text changes)
//
// Image/file/HTML clipboards are filtered here (text-only) per spec
// §11 E20. Empty strings are dropped.
class ClipboardMonitorPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  ClipboardMonitorPlugin();
  virtual ~ClipboardMonitorPlugin();

  // Disallow copy + assign.
  ClipboardMonitorPlugin(const ClipboardMonitorPlugin&) = delete;
  ClipboardMonitorPlugin& operator=(const ClipboardMonitorPlugin&) = delete;

 private:
  // Method channel dispatch.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Event channel handlers.
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListen(const flutter::EncodableValue* arguments,
           std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events);

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancel(const flutter::EncodableValue* arguments);

  // Lifecycle.
  bool StartMonitoring();
  void StopMonitoring();

  // Reads the clipboard's CF_UNICODETEXT, returns std::nullopt for non-text or
  // failure. Caller does NOT need to OpenClipboard themselves.
  std::optional<std::string> ReadClipboardText();

  // The Win32 WindowProc dispatches via this thread-local map.
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT msg, WPARAM wparam,
                                     LPARAM lparam);

  // Called on WM_CLIPBOARDUPDATE — reads text + emits to event sink.
  void OnClipboardUpdate();

  // Hidden message-only window — receives WM_CLIPBOARDUPDATE notifications.
  HWND message_window_ = nullptr;

  // FlutterEventSink — non-null only between OnListen and OnCancel.
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  // Whether AddClipboardFormatListener has succeeded (so we know to
  // RemoveClipboardFormatListener on stop).
  bool format_listener_active_ = false;

  // Channels stored as members so they outlive RegisterWithRegistrar's
  // stack frame. flutter::MethodChannel and EventChannel both deregister
  // their handlers in their destructors — losing them mid-flight breaks
  // method dispatch silently.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel_;
};

#endif  // RUNNER_CLIPBOARD_MONITOR_PLUGIN_H_

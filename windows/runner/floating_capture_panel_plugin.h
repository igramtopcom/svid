#ifndef RUNNER_FLOATING_CAPTURE_PANEL_PLUGIN_H_
#define RUNNER_FLOATING_CAPTURE_PANEL_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

// SSvid v2.1, Phase 1C.1 — Windows floating-panel attributes.
//
// Configures the spawned popup HWND with:
//   - Always-on-top via SetWindowPos(HWND_TOPMOST, ...)
//   - No-focus-steal via WS_EX_NOACTIVATE extended style — clicks on
//     the popup don't pull focus away from the user's current app
//     (mirrors macOS NSPanel.becomesKeyOnlyIfNeeded as best the WinAPI
//     allows).
//
// Registered ONLY on child engines (popups), NOT on the main runner
// window — the main app's HWND should keep normal behaviour.
//
// Channel: ssvid.floating_capture.native (popup ↔ this plugin only).
// Method:  `configurePanel` — apply attributes; idempotent.
class FloatingCapturePanelPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit FloatingCapturePanelPlugin(flutter::PluginRegistrarWindows* registrar);
  virtual ~FloatingCapturePanelPlugin();

  FloatingCapturePanelPlugin(const FloatingCapturePanelPlugin&) = delete;
  FloatingCapturePanelPlugin& operator=(const FloatingCapturePanelPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Apply the floating-panel attributes to the popup's top-level HWND.
  bool ConfigurePanel();

  // The registrar exposes the FlutterView whose ancestor HWND is the
  // popup's window. Held weakly — registrar outlives the plugin.
  flutter::PluginRegistrarWindows* registrar_;

  // Channel stored as member so it outlives RegisterWithRegistrar's
  // stack frame (same pattern as ClipboardMonitorPlugin).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
};

#endif  // RUNNER_FLOATING_CAPTURE_PANEL_PLUGIN_H_

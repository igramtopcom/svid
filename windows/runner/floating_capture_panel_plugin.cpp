#include "floating_capture_panel_plugin.h"

#include <windows.h>

#include <flutter/flutter_view.h>

#include <iostream>

// static
void FloatingCapturePanelPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<FloatingCapturePanelPlugin>(registrar);
  auto* plugin_ptr = plugin.get();

  plugin->method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "svid.floating_capture.native",
          &flutter::StandardMethodCodec::GetInstance());
  plugin->method_channel_->SetMethodCallHandler(
      [plugin_ptr](const auto& call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FloatingCapturePanelPlugin::FloatingCapturePanelPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

FloatingCapturePanelPlugin::~FloatingCapturePanelPlugin() = default;

void FloatingCapturePanelPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "configurePanel") {
    if (ConfigurePanel()) {
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Error("NO_WINDOW", "Popup HWND not attached yet");
    }
  } else {
    result->NotImplemented();
  }
}

bool FloatingCapturePanelPlugin::ConfigurePanel() {
  flutter::FlutterView* view = registrar_->GetView();
  if (view == nullptr) return false;

  HWND child_hwnd = view->GetNativeWindow();
  if (child_hwnd == nullptr) return false;

  // The FlutterView is hosted inside the runner's top-level window. Walk
  // up to the root HWND so the always-on-top + no-activate flags apply
  // to the actual popup window the user sees.
  HWND root_hwnd = ::GetAncestor(child_hwnd, GA_ROOT);
  if (root_hwnd == nullptr) root_hwnd = child_hwnd;

  // Codex audit P1 #5 fix: set extended styles FIRST so WS_EX_NOACTIVATE
  // is in effect by the time the window first appears. The previous
  // ordering used SWP_SHOWWINDOW before WS_EX_NOACTIVATE, which let
  // the window briefly activate (taking focus + flashing at the
  // spawn-default position) before the no-activate flag took effect.
  //
  // Add WS_EX_NOACTIVATE so clicks on the popup don't take focus from
  // the user's current foreground app. Closest WinAPI analogue to
  // macOS NSPanel.becomesKeyOnlyIfNeeded.
  LONG_PTR ex_style = ::GetWindowLongPtr(root_hwnd, GWL_EXSTYLE);
  ::SetWindowLongPtr(
      root_hwnd, GWL_EXSTYLE,
      ex_style | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);

  // Always-on-top above normal application windows. SWP_NOMOVE +
  // SWP_NOSIZE keep the existing position/size set by window_manager.
  // SWP_NOACTIVATE so the call itself doesn't pull focus.
  // Intentionally NOT setting SWP_SHOWWINDOW — the popup-side
  // windowManager.show() (after position restore) is the only show
  // path. See lib/floating_window_main.dart:_showWhenReady.
  ::SetWindowPos(
      root_hwnd, HWND_TOPMOST, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

  return true;
}

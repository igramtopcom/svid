//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_inappwebview_linux/flutter_inappwebview_linux_plugin.h>
#include <local_notifier/local_notifier_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) flutter_inappwebview_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterInappwebviewLinuxPlugin");
  flutter_inappwebview_linux_plugin_register_with_registrar(flutter_inappwebview_linux_registrar);
  g_autoptr(FlPluginRegistrar) local_notifier_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "LocalNotifierPlugin");
  local_notifier_plugin_register_with_registrar(local_notifier_registrar);
}

//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <app_links/app_links_plugin_c_api.h>
#include <flutter_edge_ai/flutter_edge_ai_plugin.h>
#include <flutter_local_ai/flutter_local_ai_plugin.h>
#include <url_launcher_windows/url_launcher_windows.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AppLinksPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AppLinksPluginCApi"));
  FlutterEdgeAiPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterEdgeAiPlugin"));
  FlutterLocalAiPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterLocalAiPlugin"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
}

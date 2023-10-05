#include "include/serious_python_windows/serious_python_windows_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "serious_python_windows_plugin.h"

void SeriousPythonWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  serious_python_windows::SeriousPythonWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

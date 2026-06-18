#include "serious_python_windows_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace serious_python_windows
{

  // static
  void SeriousPythonWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "serious_python_windows",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<SeriousPythonWindowsPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  SeriousPythonWindowsPlugin::SeriousPythonWindowsPlugin() {}

  SeriousPythonWindowsPlugin::~SeriousPythonWindowsPlugin() {}

  // Plugin-registration shell only — all method calls return NotImplemented.
  // Python lifecycle lives in dart_bridge[_d].dll, invoked from Dart via FFI.
  void SeriousPythonWindowsPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    result->NotImplemented();
  }

} // namespace serious_python_windows

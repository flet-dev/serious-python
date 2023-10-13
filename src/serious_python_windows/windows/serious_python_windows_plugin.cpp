#include "serious_python_windows_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

#include <Python.h>

#include <codecvt>
#include <locale>
#include <map>

namespace serious_python_windows
{

  using flutter::EncodableList;
  using flutter::EncodableMap;
  using flutter::EncodableValue;

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

  void SeriousPythonWindowsPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    const auto *arguments = std::get_if<EncodableMap>(method_call.arguments());

    if (method_call.method_name().compare("getPlatformVersion") == 0)
    {
      std::ostringstream version_stream;
      version_stream << "Windows ";
      if (IsWindows10OrGreater())
      {
        version_stream << "10+";
      }
      else if (IsWindows8OrGreater())
      {
        version_stream << "8";
      }
      else if (IsWindows7OrGreater())
      {
        version_stream << "7";
      }

      result->Success(flutter::EncodableValue(version_stream.str()));
    }
    else if (method_call.method_name().compare("runPython") == 0)
    {
      std::string exe_path;
      std::string app_path;
      flutter::EncodableList module_paths;
      flutter::EncodableMap env_vars;
      bool sync = false;

      if (arguments)
      {
        auto exe_path_it = arguments->find(EncodableValue("exePath"));
        if (exe_path_it != arguments->end())
        {
          exe_path = std::get<std::string>(exe_path_it->second);
        }

        auto app_path_it = arguments->find(EncodableValue("appPath"));
        if (app_path_it != arguments->end())
        {
          app_path = std::get<std::string>(app_path_it->second);
        }

        auto module_paths_it = arguments->find(EncodableValue("modulePaths"));
        if (module_paths_it != arguments->end() && !module_paths_it->second.IsNull())
        {
          module_paths = std::get<flutter::EncodableList>(module_paths_it->second);
        }

        auto env_vars_it = arguments->find(EncodableValue("environmentVariables"));
        if (env_vars_it != arguments->end() && !env_vars_it->second.IsNull())
        {
          env_vars = std::get<flutter::EncodableMap>(env_vars_it->second);
        }

        auto sync_it = arguments->find(EncodableValue("sync"));
        if (sync_it != arguments->end())
        {
          sync = std::get<bool>(sync_it->second);
        }
      }
      else
      {
        result->Error("ARGUMENT_ERROR", "appPath argument is missing.");
        return;
      }

      printf("exePath: %s\n", exe_path.c_str());
      printf("appPath: %s\n", app_path.c_str());
      for (const auto &item : module_paths)
      {
        if (auto str_value = std::get_if<std::string>(&item))
        {
          // Use *int_value here
          printf("module_path: %s\n", str_value->c_str());
        }
      }

      for (const auto &kv : env_vars)
      {
        auto key = kv.first;
        auto value = kv.second;
        if (auto str_key = std::get_if<std::string>(&key);
            auto str_value = std::get_if<std::string>(&value))
        {
          // Use *str_value here
          printf("env_var: %s=%s\n", str_key->c_str(), str_value->c_str());
        }
      }

      printf("sync: %s\n", sync ? "true" : "false");

      Py_Initialize();
      // FILE* file = _Py_fopen(script_path.c_str(), "r");
      // if (file != NULL) {
      //   PyRun_SimpleFileEx(file, script_path.c_str(), 1);
      // }
      Py_Finalize();

      result->Success(flutter::EncodableValue(app_path));
    }
    else
    {
      result->NotImplemented();
    }
  }

} // namespace serious_python_windows

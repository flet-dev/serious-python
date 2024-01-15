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
#include <stdlib.h>
#include <filesystem>
#include <format>
#include <vector>
#include <string>
#include <thread>

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
      std::string script;
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

        auto script_it = arguments->find(EncodableValue("script"));
        if (script_it != arguments->end())
        {
          script = std::get<std::string>(script_it->second);
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
        if (sync_it != arguments->end() && !sync_it->second.IsNull())
        {
          sync = std::get<bool>(sync_it->second);
        }
      }
      else
      {
        result->Error("ARGUMENT_ERROR", "arguments is missing.");
        return;
      }

      std::string exe_dir = std::filesystem::path(exe_path).parent_path().string();
      std::string app_dir = std::filesystem::path(app_path).parent_path().string();

      printf("exePath: %s\n", exe_path.c_str());
      printf("exeDir: %s\n", exe_dir.c_str());
      printf("appPath: %s\n", app_path.c_str());

      std::vector<std::string> python_paths;

      // add user module paths to the top
      for (const auto &item : module_paths)
      {
        if (auto str_value = std::get_if<std::string>(&item))
        {
          printf("module_path: %s\n", str_value->c_str());
          python_paths.push_back(*str_value);
        }
      }

      // add system paths
      python_paths.push_back(app_dir);
      python_paths.push_back(app_dir + "\\__pypackages__");
      python_paths.push_back(exe_dir + "\\DLLs");
      python_paths.push_back(exe_dir + "\\Lib");
      python_paths.push_back(exe_dir + "\\Lib\\site-packages");

      std::string python_path;
      for (int i = 0; i < python_paths.size(); i++)
      {
        python_path += python_paths[i];
        if (i < python_paths.size() - 1)
        { // Don't add separator after the last element
          python_path += ";";
        }
      }

      printf("PYTHONPATH: %s\n", python_path.c_str());

      // set python-related env vars
      _putenv_s("PYTHONINSPECT", "1");
      _putenv_s("PYTHONOPTIMIZE", "2");
      _putenv_s("PYTHONDONTWRITEBYTECODE", "1");
      _putenv_s("PYTHONNOUSERSITE", "1");
      _putenv_s("PYTHONUNBUFFERED", "1");
      _putenv_s("LC_CTYPE", "UTF-8");
      _putenv_s("PYTHONHOME", exe_dir.c_str());
      _putenv_s("PYTHONPATH", python_path.c_str());

      // set user environment variables
      for (const auto &kv : env_vars)
      {
        auto key = kv.first;
        auto value = kv.second;
        if (auto str_key = std::get_if<std::string>(&key);
            auto str_value = std::get_if<std::string>(&value))
        {
          printf("env_var: %s=%s\n", str_key->c_str(), str_value->c_str());
          _putenv_s(str_key->c_str(), str_value->c_str());
        }
      }

      printf("sync: %s\n", sync ? "true" : "false");

      // run program
      if (sync)
      {
        if (script.empty())
        {
          printf("Running Python program synchronously...");
          RunPythonProgram(app_path);
        }
        else
        {
          printf("Running Python script synchronously...");
          RunPythonScript(script);
        }
      }
      else
      {
        if (script.empty())
        {
          printf("Running Python program asynchronously...");
          RunPythonProgramAsync(app_path);
        }
        else
        {
          printf("Running Python script asynchronously...");
          RunPythonScriptAsync(script);
        }
      }

      result->Success(flutter::EncodableValue(app_path));
    }
    else
    {
      result->NotImplemented();
    }
  }

  void SeriousPythonWindowsPlugin::RunPythonProgramAsync(std::string appPath)
  {
    // Create a new thread that runs the program
    std::thread pyThread(&SeriousPythonWindowsPlugin::RunPythonProgram, this, appPath);

    // Detach the thread so it runs independently
    pyThread.detach();
  }

  void SeriousPythonWindowsPlugin::RunPythonScriptAsync(std::string script)
  {
    // Create a new thread that runs the script
    std::thread pyThread(&SeriousPythonWindowsPlugin::RunPythonScript, this, script);

    // Detach the thread so it runs independently
    pyThread.detach();
  }

  void SeriousPythonWindowsPlugin::RunPythonProgram(std::string appPath)
  {
    Py_Initialize();

    FILE *file;
    errno_t err = fopen_s(&file, appPath.c_str(), "r");
    if (err == 0 && file != NULL)
    {
      PyRun_SimpleFileEx(file, appPath.c_str(), 1);
      fclose(file);
    }

    Py_Finalize();
  }

  void SeriousPythonWindowsPlugin::RunPythonScript(std::string script)
  {
    Py_Initialize();

    PyRun_SimpleString(script.c_str());

    Py_Finalize();
  }

} // namespace serious_python_windows

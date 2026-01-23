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

namespace
{
  // Convert UTF-8 text from Flutter/Dart to UTF-16 for Windows APIs.
  std::wstring Utf8ToWide(const std::string &value)
  {
    if (value.empty())
    {
      return L"";
    }
    UINT codepage = CP_UTF8;
    DWORD flags = MB_ERR_INVALID_CHARS;
    int size = MultiByteToWideChar(codepage, flags, value.data(),
                                   static_cast<int>(value.size()), nullptr, 0);
    if (size <= 0)
    {
      codepage = CP_ACP;
      flags = 0;
      size = MultiByteToWideChar(codepage, flags, value.data(),
                                 static_cast<int>(value.size()), nullptr, 0);
    }
    if (size <= 0)
    {
      return L"";
    }
    std::wstring wide(size, L'\0');
    MultiByteToWideChar(codepage, flags, value.data(),
                        static_cast<int>(value.size()), wide.data(), size);
    return wide;
  }

  // Convert UTF-16 Windows strings to UTF-8 for logs/interop.
  std::string WideToUtf8(const std::wstring &value)
  {
    if (value.empty())
    {
      return "";
    }
    int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                   static_cast<int>(value.size()), nullptr, 0,
                                   nullptr, nullptr);
    if (size <= 0)
    {
      return "";
    }
    std::string utf8(size, '\0');
    WideCharToMultiByte(CP_UTF8, 0, value.data(),
                        static_cast<int>(value.size()), utf8.data(), size,
                        nullptr, nullptr);
    return utf8;
  }

  // Set environment variables using Unicode-safe Windows APIs.
  void SetEnvWide(const std::wstring &key, const std::wstring &value)
  {
    if (key.empty())
    {
      return;
    }
    _wputenv_s(key.c_str(), value.c_str());
    SetEnvironmentVariableW(key.c_str(), value.c_str());
  }

  // Join paths without narrowing, preserving non-ASCII characters.
  std::wstring JoinPaths(const std::vector<std::wstring> &paths, wchar_t sep)
  {
    std::wstring joined;
    for (size_t i = 0; i < paths.size(); ++i)
    {
      joined += paths[i];
      if (i + 1 < paths.size())
      {
        joined += sep;
      }
    }
    return joined;
  }
}

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

      // Treat Dart strings as UTF-8 to avoid lossy conversions.
      std::filesystem::path exe_path_fs(Utf8ToWide(exe_path));
      std::filesystem::path app_path_fs(Utf8ToWide(app_path));
      std::wstring exe_dir = exe_path_fs.parent_path().wstring();
      std::wstring app_dir = app_path_fs.parent_path().wstring();

      printf("exePath: %s\n", exe_path.c_str());
      printf("exeDir: %s\n", WideToUtf8(exe_dir).c_str());
      printf("appPath: %s\n", app_path.c_str());

      std::vector<std::wstring> python_paths;

      // add user module paths to the top
      for (const auto &item : module_paths)
      {
        if (auto str_value = std::get_if<std::string>(&item))
        {
          printf("module_path: %s\n", str_value->c_str());
          python_paths.push_back(Utf8ToWide(*str_value));
        }
      }

      // add system paths
      python_paths.push_back(app_dir);
      python_paths.push_back(app_dir + L"\\__pypackages__");
      python_paths.push_back(exe_dir + L"\\site-packages");
      python_paths.push_back(exe_dir + L"\\DLLs");
      python_paths.push_back(exe_dir + L"\\Lib");
      python_paths.push_back(exe_dir + L"\\Lib\\site-packages");

      std::wstring python_path = JoinPaths(python_paths, L';');
      printf("PYTHONPATH: %s\n", WideToUtf8(python_path).c_str());

      // Set Python-related env vars using wide APIs so Unicode paths survive.
      SetEnvWide(L"PYTHONINSPECT", L"1");
      SetEnvWide(L"PYTHONDONTWRITEBYTECODE", L"1");
      SetEnvWide(L"PYTHONNOUSERSITE", L"1");
      SetEnvWide(L"PYTHONUNBUFFERED", L"1");
      SetEnvWide(L"LC_CTYPE", L"UTF-8");
      SetEnvWide(L"PYTHONHOME", exe_dir);
      SetEnvWide(L"PYTHONPATH", python_path);

      // Set user-provided env vars as UTF-16 for Windows.
      for (const auto &kv : env_vars)
      {
        auto key = kv.first;
        auto value = kv.second;
        if (auto str_key = std::get_if<std::string>(&key);
            auto str_value = std::get_if<std::string>(&value))
        {
          printf("env_var: %s=%s\n", str_key->c_str(), str_value->c_str());
          SetEnvWide(Utf8ToWide(*str_key), Utf8ToWide(*str_value));
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
    // Use wide fopen to open Unicode paths on Windows.
    std::wstring appPathWide = Utf8ToWide(appPath);
    errno_t err = _wfopen_s(&file, appPathWide.c_str(), L"r");
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

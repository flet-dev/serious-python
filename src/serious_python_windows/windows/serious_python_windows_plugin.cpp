#define _CRT_SECURE_NO_WARNINGS

#include "serious_python_windows_plugin.h"

#include <windows.h>
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <Python.h>

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <chrono>
#include <ctime>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace serious_python_windows {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

static void Log(const std::string& message) {
  /*
  std::ofstream logfile("C:\\temp\\serious_python_debug.log", std::ios::app);
  if (logfile.is_open()) {
      auto now = std::chrono::system_clock::now();
      std::time_t now_time = std::chrono::system_clock::to_time_t(now);
      logfile << std::ctime(&now_time) << " - " << message << std::endl;
      logfile.close();
  }
  */
}

bool SeriousPythonWindowsPlugin::python_initialized_ = false;
std::mutex SeriousPythonWindowsPlugin::python_mutex_;
static PyThreadState* main_thread_state = nullptr;

void SeriousPythonWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  Log("RegisterWithRegistrar called");

  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "serious_python_windows",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<SeriousPythonWindowsPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
  Log("RegisterWithRegistrar finished");
}

SeriousPythonWindowsPlugin::SeriousPythonWindowsPlugin() {
  Log("SeriousPythonWindowsPlugin constructor");
}

SeriousPythonWindowsPlugin::~SeriousPythonWindowsPlugin() {
  Log("Destructor called");
  std::lock_guard<std::mutex> lock(python_mutex_);
  if (python_initialized_) {
    if (main_thread_state) {
      Log("Restoring main thread state before finalization");
      PyEval_RestoreThread(main_thread_state);
      main_thread_state = nullptr;
    }
    Log("Finalizing Python interpreter");
    Py_Finalize();
    python_initialized_ = false;
    Log("Python finalized");
  }
}

void SeriousPythonWindowsPlugin::EnsurePythonInitialized() {
  std::lock_guard<std::mutex> lock(python_mutex_);
  if (!python_initialized_) {
    Log("Initializing Python interpreter...");
    Py_Initialize();
    if (!Py_IsInitialized()) {
      Log("ERROR: Python initialization failed!");
      return;
    }
    // Release GIL and save main thread state to allow other threads to acquire GIL
    main_thread_state = PyEval_SaveThread();
    python_initialized_ = true;
    Log("Python initialized successfully, GIL released.");
  }
}

void SeriousPythonWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  Log("HandleMethodCall called, method: " + method_call.method_name());

  const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());

  if (method_call.method_name().compare("getPlatformVersion") == 0) {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
    Log("getPlatformVersion returned");
    return;
  }
  else if (method_call.method_name().compare("runPython") == 0) {
    Log("runPython method detected");

    std::string exe_path;
    std::string app_path;
    std::string script;
    EncodableList module_paths;
    EncodableMap env_vars;
    bool sync = false;

    if (arguments) {
      auto exe_path_it = arguments->find(EncodableValue("exePath"));
      if (exe_path_it != arguments->end())
        exe_path = std::get<std::string>(exe_path_it->second);

      auto app_path_it = arguments->find(EncodableValue("appPath"));
      if (app_path_it != arguments->end())
        app_path = std::get<std::string>(app_path_it->second);

      auto script_it = arguments->find(EncodableValue("script"));
      if (script_it != arguments->end())
        script = std::get<std::string>(script_it->second);

      auto module_paths_it = arguments->find(EncodableValue("modulePaths"));
      if (module_paths_it != arguments->end() && !module_paths_it->second.IsNull())
        module_paths = std::get<EncodableList>(module_paths_it->second);

      auto env_vars_it = arguments->find(EncodableValue("environmentVariables"));
      if (env_vars_it != arguments->end() && !env_vars_it->second.IsNull())
        env_vars = std::get<EncodableMap>(env_vars_it->second);

      auto sync_it = arguments->find(EncodableValue("sync"));
      if (sync_it != arguments->end() && !sync_it->second.IsNull())
        sync = std::get<bool>(sync_it->second);
    } else {
      Log("ERROR: arguments is missing");
      result->Error("ARGUMENT_ERROR", "arguments is missing.");
      return;
    }

    Log("exePath: " + exe_path);
    Log("appPath: " + app_path);
    Log("script: " + script);
    Log("sync: " + std::to_string(sync));

    std::string exe_dir = std::filesystem::path(exe_path).parent_path().string();
    std::string app_dir = std::filesystem::path(app_path).parent_path().string();

    std::vector<std::string> python_paths;
    for (const auto& item : module_paths) {
      if (auto str_value = std::get_if<std::string>(&item))
        python_paths.push_back(*str_value);
    }
    python_paths.push_back(app_dir);
    python_paths.push_back(app_dir + "\\__pypackages__");
    python_paths.push_back(exe_dir + "\\site-packages");
    python_paths.push_back(exe_dir + "\\DLLs");
    python_paths.push_back(exe_dir + "\\Lib");
    python_paths.push_back(exe_dir + "\\Lib\\site-packages");

    std::string python_path;
    for (size_t i = 0; i < python_paths.size(); ++i) {
      python_path += python_paths[i];
      if (i < python_paths.size() - 1) python_path += ";";
    }

    _putenv_s("PYTHONINSPECT", "1");
    _putenv_s("PYTHONDONTWRITEBYTECODE", "1");
    _putenv_s("PYTHONNOUSERSITE", "1");
    _putenv_s("PYTHONUNBUFFERED", "1");
    _putenv_s("LC_CTYPE", "UTF-8");
    _putenv_s("PYTHONHOME", exe_dir.c_str());
    _putenv_s("PYTHONPATH", python_path.c_str());

    for (const auto& kv : env_vars) {
      auto key = kv.first;
      auto value = kv.second;
      if (auto str_key = std::get_if<std::string>(&key);
          auto str_value = std::get_if<std::string>(&value)) {
        _putenv_s(str_key->c_str(), str_value->c_str());
      }
    }

    Log("PYTHONHOME set to: " + exe_dir);
    Log("PYTHONPATH set to: " + python_path);

    EnsurePythonInitialized();

    if (sync) {
      // For sync execution, we need to re-acquire GIL because main thread released it.
      PyGILState_STATE gstate = PyGILState_Ensure();
      if (script.empty()) {
        RunPythonProgram(app_path);
      } else {
        RunPythonScript(script);
      }
      PyGILState_Release(gstate);
    } else {
      if (script.empty()) {
        RunPythonProgramAsync(app_path);
      } else {
        RunPythonScriptAsync(script);
      }
    }

    result->Success(flutter::EncodableValue(app_path));
    Log("runPython finished, returning success");
  }
  else {
    result->NotImplemented();
    Log("Method not implemented: " + method_call.method_name());
  }
}

void SeriousPythonWindowsPlugin::RunPythonProgramAsync(std::string appPath) {
  Log("RunPythonProgramAsync starting for: " + appPath);
  std::thread pyThread([this, appPath]() {
    RunPythonProgram(appPath);
  });
  pyThread.detach();
  Log("RunPythonProgramAsync thread detached");
}

void SeriousPythonWindowsPlugin::RunPythonScriptAsync(std::string script) {
  Log("RunPythonScriptAsync starting");
  std::thread pyThread([this, script]() {
    RunPythonScript(script);
  });
  pyThread.detach();
  Log("RunPythonScriptAsync thread detached");
}

void SeriousPythonWindowsPlugin::RunPythonProgram(std::string appPath) {
  Log("RunPythonProgram entered for: " + appPath);
  PyGILState_STATE gstate = PyGILState_Ensure();
  Log("GIL acquired");

  int ret = PyRun_SimpleString("print('Hello from inline Python')\nimport sys; sys.stdout.flush()");
  if (ret != 0) {
    Log("Inline Python test failed, code=" + std::to_string(ret));
    PyErr_Print();
  } else {
    Log("Inline Python test succeeded");
  }

  FILE* file;
  errno_t err = fopen_s(&file, appPath.c_str(), "r");
  if (err == 0 && file != nullptr) {
    Log("File opened successfully: " + appPath);
    ret = PyRun_SimpleFileEx(file, appPath.c_str(), 1);
    if (ret != 0) {
      Log("Python file execution failed with code " + std::to_string(ret));
      PyErr_Print();
    } else {
      Log("Python file executed successfully");
    }
    fclose(file);
  } else {
    Log("Failed to open Python file: " + appPath + ", errno=" + std::to_string(err));
  }

  PyGILState_Release(gstate);
  Log("GIL released, RunPythonProgram finished");
}

void SeriousPythonWindowsPlugin::RunPythonScript(std::string script) {
  Log("RunPythonScript entered");
  PyGILState_STATE gstate = PyGILState_Ensure();
  Log("GIL acquired");

  int ret = PyRun_SimpleString(script.c_str());
  if (ret != 0) {
    Log("Python script execution failed with code " + std::to_string(ret));
    PyErr_Print();
  } else {
    Log("Python script executed successfully");
  }

  PyGILState_Release(gstate);
  Log("GIL released, RunPythonScript finished");
}

}  // namespace serious_python_windows
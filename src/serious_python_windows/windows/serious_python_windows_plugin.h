#ifndef FLUTTER_PLUGIN_SERIOUS_PYTHON_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_SERIOUS_PYTHON_WINDOWS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <mutex>
#include <string>

namespace serious_python_windows {

class SeriousPythonWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  SeriousPythonWindowsPlugin();
  virtual ~SeriousPythonWindowsPlugin();

  // Disallow copy and assign.
  SeriousPythonWindowsPlugin(const SeriousPythonWindowsPlugin&) = delete;
  SeriousPythonWindowsPlugin& operator=(const SeriousPythonWindowsPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  void RunPythonProgram(std::string appPath);
  void RunPythonProgramAsync(std::string appPath);
  void RunPythonScript(std::string script);
  void RunPythonScriptAsync(std::string script);

  static void EnsurePythonInitialized();

  static bool python_initialized_;
  static std::mutex python_mutex_;
};

}  // namespace serious_python_windows

#endif  // FLUTTER_PLUGIN_SERIOUS_PYTHON_WINDOWS_PLUGIN_H_
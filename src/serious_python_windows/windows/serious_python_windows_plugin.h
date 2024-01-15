#ifndef FLUTTER_PLUGIN_SERIOUS_PYTHON_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_SERIOUS_PYTHON_WINDOWS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace serious_python_windows
{

    class SeriousPythonWindowsPlugin : public flutter::Plugin
    {
    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

        SeriousPythonWindowsPlugin();

        virtual ~SeriousPythonWindowsPlugin();

        // Disallow copy and assign.
        SeriousPythonWindowsPlugin(const SeriousPythonWindowsPlugin &) = delete;
        SeriousPythonWindowsPlugin &operator=(const SeriousPythonWindowsPlugin &) = delete;

        // Called when a method is called on this plugin's channel from Dart.
        void HandleMethodCall(
            const flutter::MethodCall<flutter::EncodableValue> &method_call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

        void RunPythonProgram(std::string appPath);
        void RunPythonProgramAsync(std::string appPath);

        void RunPythonScript(std::string script);
        void RunPythonScriptAsync(std::string script);
    };

} // namespace serious_python_windows

#endif // FLUTTER_PLUGIN_SERIOUS_PYTHON_WINDOWS_PLUGIN_H_

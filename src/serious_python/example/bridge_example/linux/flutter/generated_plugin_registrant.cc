//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <serious_python_linux/serious_python_linux_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) serious_python_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "SeriousPythonLinuxPlugin");
  serious_python_linux_plugin_register_with_registrar(serious_python_linux_registrar);
}

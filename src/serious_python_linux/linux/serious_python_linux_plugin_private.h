#include <flutter_linux/flutter_linux.h>

#include "include/serious_python_linux/serious_python_linux_plugin.h"

// This file exposes some plugin internals for unit testing. See
// https://github.com/flutter/flutter/issues/88724 for current limitations
// in the unit-testable API.

// Handles the getPlatformVersion method call.
FlMethodResponse *get_platform_version();

void run_python_program(gchar *appPath);
gpointer run_python_program_async(gpointer data);

void run_python_script(gchar *script);
gpointer run_python_script_async(gpointer data);
#include "include/serious_python_linux/serious_python_linux_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>
#include <string>

#include "serious_python_linux_plugin_private.h"

#include <Python.h>

#define SERIOUS_PYTHON_LINUX_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), serious_python_linux_plugin_get_type(), \
                              SeriousPythonLinuxPlugin))

struct _SeriousPythonLinuxPlugin
{
  GObject parent_instance;
};

G_DEFINE_TYPE(SeriousPythonLinuxPlugin, serious_python_linux_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void serious_python_linux_plugin_handle_method_call(
    SeriousPythonLinuxPlugin *self,
    FlMethodCall *method_call)
{
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar *method = fl_method_call_get_name(method_call);
  FlValue *args = fl_method_call_get_args(method_call);

  if (strcmp(method, "getPlatformVersion") == 0)
  {
    response = get_platform_version();
  }
  else if (strcmp(method, "runPython") == 0)
  {
    if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    {
      return;
    }

    // exePath
    FlValue *exe_path = fl_value_lookup_string(args, "exePath");
    if (exe_path == nullptr)
    {
      return;
    }

    gchar *exe_dir = g_path_get_dirname(fl_value_to_string(exe_path));

    // appPath
    FlValue *app_path = fl_value_lookup_string(args, "appPath");
    if (app_path == nullptr)
    {
      return;
    }

    gchar *app_dir = g_path_get_dirname(fl_value_to_string(app_path));

    // script
    FlValue *script = fl_value_lookup_string(args, "script");

    // sync
    bool sync = false;
    g_autoptr(FlValue) sync_key = fl_value_new_string("sync");
    FlValue *sync_value = fl_value_lookup(args, sync_key);
    if (sync_value != nullptr && fl_value_get_type(sync_value) == FL_VALUE_TYPE_BOOL)
    {
      sync = fl_value_get_bool(sync_value);
    }

    // modulePaths
    size_t module_paths_size = 0;

    g_autoptr(FlValue) module_paths_key = fl_value_new_string("modulePaths");
    FlValue *module_paths = fl_value_lookup(args, module_paths_key);
    if (module_paths != nullptr && fl_value_get_type(module_paths) == FL_VALUE_TYPE_LIST)
    {
      module_paths_size = fl_value_get_length(module_paths);
      printf("modulePaths is a LIST: %zu\n", module_paths_size);
    }

    gchar **module_paths_str_array = g_new(gchar *, module_paths_size + 4 /* standard modules */ + 1 /* for the NULL at the end */);

    // user module paths
    size_t i = 0;
    if (module_paths_size > 0)
    {
      for (; i < module_paths_size; i++)
      {
        FlValue *v = fl_value_get_list_value(module_paths, i);
        printf("modulePath: %s\n", fl_value_to_string(v));
        module_paths_str_array[i] = g_strdup(fl_value_to_string(v));
      }
    }

    // system module paths
    module_paths_str_array[i++] = g_strdup_printf("%s", app_dir);
    module_paths_str_array[i++] = g_strdup_printf("%s/__pypackages__", app_dir);
    module_paths_str_array[i++] = g_strdup_printf("%s/python3.11", exe_dir);
    module_paths_str_array[i++] = g_strdup_printf("%s/python3.11/site-packages", exe_dir);
    module_paths_str_array[i++] = NULL;

    gchar *module_paths_str = g_strjoinv(":", module_paths_str_array); // join with comma and space as separators
    printf("modulePaths joined string: %s\n", module_paths_str);

    // environmentVariables
    g_setenv("PYTHONINSPECT", "1", TRUE);
    g_setenv("PYTHONOPTIMIZE", "2", TRUE);
    g_setenv("PYTHONDONTWRITEBYTECODE", "1", TRUE);
    g_setenv("PYTHONNOUSERSITE", "1", TRUE);
    g_setenv("PYTHONUNBUFFERED", "1", TRUE);
    g_setenv("LC_CTYPE", "UTF-8", TRUE);
    g_setenv("PYTHONHOME", exe_dir, TRUE);
    g_setenv("PYTHONPATH", module_paths_str, TRUE);

    g_autoptr(FlValue) env_vars_key = fl_value_new_string("environmentVariables");
    FlValue *env_vars_map = fl_value_lookup(args, env_vars_key);
    if (env_vars_map != nullptr && fl_value_get_type(env_vars_map) == FL_VALUE_TYPE_MAP)
    {
      size_t size = fl_value_get_length(env_vars_map);
      printf("environmentVariables is a MAP: %zu\n", size);
      for (size_t i = 0; i < size; i++)
      {
        FlValue *key = fl_value_get_map_key(env_vars_map, i);
        FlValue *val = fl_value_lookup(env_vars_map, key);
        printf("env var %s=%s\n", fl_value_to_string(key), fl_value_to_string(val));
        g_setenv(fl_value_to_string(key), fl_value_to_string(val), TRUE);
      }
    }

    printf("exe_dir: %s\n", exe_dir);
    printf("app_dir: %s\n", app_dir);
    printf("sync: %s\n", sync ? "true" : "false");

    g_strfreev(module_paths_str_array); // free the array and its elements
    g_free(module_paths_str);           // free the joined string

    if (sync)
    {
      if (script != nullptr)
      {
        run_python_script(fl_value_to_string(script));
      }
      else
      {
        run_python_program(fl_value_to_string(app_path));
      }
    }
    else
    {
      if (script != nullptr)
      {
        g_thread_new(NULL, run_python_script_async, g_strdup(fl_value_to_string(script)));
      }
      else
      {
        g_thread_new(NULL, run_python_program_async, g_strdup(fl_value_to_string(app_path)));
      }
    }

    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_string("")));
  }
  else
  {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

void run_python_program(gchar *appPath)
{
  Py_Initialize();

  FILE *file = fopen(appPath, "r");
  if (file != NULL)
  {
    PyRun_SimpleFileEx(file, appPath, 1);
  }
  else
  {
    printf("Failed to open Python app file: %s\n", appPath);
  }

  Py_Finalize();
}

void run_python_script(gchar *script)
{
  Py_Initialize();

  PyRun_SimpleString(script);

  Py_Finalize();
}

gpointer run_python_program_async(gpointer data)
{
  run_python_program((gchar *)data);
  return NULL;
}

gpointer run_python_script_async(gpointer data)
{
  run_python_script((gchar *)data);
  return NULL;
}

FlMethodResponse *get_platform_version()
{
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void serious_python_linux_plugin_dispose(GObject *object)
{
  G_OBJECT_CLASS(serious_python_linux_plugin_parent_class)->dispose(object);
}

static void serious_python_linux_plugin_class_init(SeriousPythonLinuxPluginClass *klass)
{
  G_OBJECT_CLASS(klass)->dispose = serious_python_linux_plugin_dispose;
}

static void serious_python_linux_plugin_init(SeriousPythonLinuxPlugin *self) {}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data)
{
  SeriousPythonLinuxPlugin *plugin = SERIOUS_PYTHON_LINUX_PLUGIN(user_data);
  serious_python_linux_plugin_handle_method_call(plugin, method_call);
}

void serious_python_linux_plugin_register_with_registrar(FlPluginRegistrar *registrar)
{
  SeriousPythonLinuxPlugin *plugin = SERIOUS_PYTHON_LINUX_PLUGIN(
      g_object_new(serious_python_linux_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "serious_python_linux",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}

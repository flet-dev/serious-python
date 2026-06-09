import sys
from setuptools import Extension, setup

NATIVE_ROOT = "../native"

extra_link_args = []
# dlopen/dlsym on Linux live in libdl. macOS rolls them into libSystem.
# Windows uses LoadLibrary/GetProcAddress from kernel32 (implicit).
if sys.platform.startswith("linux"):
    extra_link_args.append("-ldl")

setup(
    ext_modules=[
        Extension(
            "dart_bridge",
            # Shim only — the Dart-callable core and its dart_api_dl.c live in
            # libflet_bridge (built by the Flutter plugin) and are resolved at
            # PyInit time via dlsym / GetProcAddress.
            sources=[f"{NATIVE_ROOT}/dart_bridge_shim.c"],
            # Limited API / abi3: one .so per platform works for any Python
            # 3.12+. Keep this in lockstep with Py_LIMITED_API in
            # dart_bridge_shim.c.
            define_macros=[("Py_LIMITED_API", "0x030c0000")],
            py_limited_api=True,
            extra_link_args=extra_link_args,
        )
    ],
)

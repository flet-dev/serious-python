from setuptools import Extension, setup

NATIVE_ROOT = "../native"

setup(
    ext_modules=[
        Extension(
            "dart_bridge",
            sources=[
                f"{NATIVE_ROOT}/dart_bridge.c",
                f"{NATIVE_ROOT}/dart_api/dart_api_dl.c",
            ],
            include_dirs=[NATIVE_ROOT],
            # Limited API / abi3: one .so per platform works for any Python
            # 3.12+. Keep this in lockstep with Py_LIMITED_API in dart_bridge.c.
            define_macros=[("Py_LIMITED_API", "0x030c0000")],
            py_limited_api=True,
        )
    ],
)

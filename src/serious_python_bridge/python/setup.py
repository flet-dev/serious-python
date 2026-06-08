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
        )
    ],
)

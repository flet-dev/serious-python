# Consumer ProGuard/R8 rules — automatically applied to apps that depend on
# serious_python_android.
#
# pyjnius and the native runtime look these classes (and their members) up by
# name via JNI/reflection at runtime. Without these keep rules, release-mode R8
# minification renames/strips them — e.g. PythonActivity -> "C.f" and its static
# `mActivity` field is dropped — which breaks pyjnius with:
#   pyjnius: not available on this platform -
#     type object 'C.f' has no attribute 'mActivity'
-keep class com.flet.serious_python_android.** { *; }

import 'dart:ffi' as ffi;

import 'gen.dart';

export 'gen.dart';

/// A variable to override the python dynamic library location on your computer
final pyLib = ffi.DynamicLibrary.open("libpython3.10.so");

CPython? _cpython;

/// Dynamic library
CPython get cpython => _cpython ?? (_cpython = CPython(pyLib));

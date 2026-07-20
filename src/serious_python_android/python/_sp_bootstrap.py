"""serious_python Android import bootstrap.

Installed by the dart-bridge embedder *before* `site` runs, via the fixed call::

    import _sp_bootstrap; _sp_bootstrap.install()

It registers a `sys.meta_path` finder that resolves native CPython extension
modules which the build relocated into `jniLibs/<abi>/` as real `lib<mangled>.so`
files (loaded by basename through the Android linker namespace, exactly like
`libdart_bridge.so`). Pure `.py`/`.pyc` modules are left to `zipimport` /
`FileFinder` — this finder returns `None` for them.

For every relocated extension the build leaves a `.soref` marker at the module's
original path; its content is the `lib<mangled>.so` filename. The marker is read
**lazily** in `find_spec` via the frozen `zipimport` `get_data` API (for zip
entries) or a plain `open` (for entries extracted to disk, e.g. `extract.zip`).

CRITICAL: this module must load and run *before any native module is resolvable*,
so it imports **only builtin/frozen** machinery — `sys`, `zipimport`,
`importlib.machinery` — and never `zipfile`/`struct`/`zlib` (which would be
a chicken-and-egg: those are themselves native).
"""

import sys
import posix  # builtin (native-free): read env without importing os
import zipimport
from importlib.machinery import ExtensionFileLoader, ModuleSpec

_MARKER_SUFFIX = ".soref"
_installed = False


def _native_lib_dir():
    # nativeLibraryDir, exported by AndroidPlugin before Py_Initialize. Under legacy
    # packaging the mangled libs are extracted there, so an absolute origin lets the
    # interpreter dlopen them (some Android CPython builds prepend "./" to a no-slash
    # origin, which breaks a bare-soname namespace lookup). Empty under modern
    # packaging -> fall back to bare soname (linker-namespace resolution).
    v = posix.environ.get(b"ANDROID_NATIVE_LIBRARY_DIR")
    return v.decode("utf-8") if v else None


def _apk_native_prefix():
    # base.apk!/lib/<abi>/ — Bionic zip-path to libs mmap'd from the APK under modern
    # packaging (useLegacyPackaging=false), where libs are NOT extracted to disk.
    v = posix.environ.get(b"ANDROID_APK_NATIVE_PREFIX")
    return v.decode("utf-8") if v else None


class _SorefFinder:
    """meta_path finder: dotted name -> jniLibs lib via its `.soref` marker."""

    def __init__(self):
        # Cache one zipimporter per zip sys.path entry. Value is None for entries
        # that are not zips (plain directories) so we don't retry zipimporter().
        self._zi_cache = {}
        self._native_dir = _native_lib_dir()
        self._apk_prefix = _apk_native_prefix()

    def _zipimporter(self, entry):
        try:
            return self._zi_cache[entry]
        except KeyError:
            try:
                zi = zipimport.zipimporter(entry)
            except Exception:
                zi = None  # not a zip (e.g. a directory)
            self._zi_cache[entry] = zi
            return zi

    def _read_marker(self, member):
        """Return `(soref_bytes, sys.path entry)` for `member`, or
        `(None, None)` if absent.

        Probes every current `sys.path` entry: zip entries via the frozen
        `zipimport.get_data` (known member, no native deps), directory entries
        via a plain `open` (covers packages unpacked from `extract.zip`). The
        winning entry is returned too so a package whose `__init__` is the
        native extension can locate its pure-Python submodules beside it.
        """
        for entry in sys.path:
            if not entry:
                continue
            zi = self._zipimporter(entry)
            if zi is not None:
                try:
                    return zi.get_data(member), entry  # archive-relative member
                except Exception:
                    continue
            else:
                # Directory entry: try the marker as a real file on disk.
                path = entry + "/" + member
                try:
                    with open(path, "rb") as f:
                        return f.read(), entry
                except OSError:
                    continue
        return None, None

    def find_spec(self, fullname, path=None, target=None):
        base = fullname.replace(".", "/")
        # A plain extension module: its marker is "<dotted>.soref".
        data, entry = self._read_marker(base + _MARKER_SUFFIX)
        is_package = False
        if data is None:
            # A package whose __init__ IS the native extension (e.g. apsw ships
            # apsw/__init__.<abi>.so): the marker sits at "<dotted>/__init__.soref".
            data, entry = self._read_marker(base + "/__init__" + _MARKER_SUFFIX)
            is_package = data is not None
        if data is None:
            return None  # not a relocated native module -> let others handle it
        soname = data.decode("utf-8").strip()
        # Resolve the lib to an absolute origin (CPython prepends "./" to a no-slash
        # origin, which breaks bare-soname loading). Prefer the extracted copy under
        # nativeLibraryDir (legacy packaging); else the Bionic APK zip-path (modern
        # packaging, mmap'd from the APK, never extracted).
        origin = soname
        if self._native_dir:
            cand = self._native_dir + "/" + soname
            try:
                open(cand, "rb").close()
                origin = cand
            except OSError:
                pass
        if origin == soname and self._apk_prefix:
            origin = self._apk_prefix + soname
        loader = ExtensionFileLoader(fullname, origin)
        spec = ModuleSpec(fullname, loader, origin=origin)
        if is_package and entry is not None:
            # The native __init__ lives in jniLibs, but the package's pure-Python
            # submodules (e.g. apsw.ext) sit at "<entry>/<dotted>/" in the winning
            # sys.path entry (sitepackages.zip or an extract.zip dir). Point
            # __path__ there so `import <pkg>.<sub>` resolves via the normal
            # zipimport/FileFinder machinery.
            spec.submodule_search_locations = [entry + "/" + base]
        return spec


def _install_finder():
    """Insert the finder at the front of `sys.meta_path` (idempotent)."""
    global _installed
    if _installed:
        return
    # Bootstrap audit: any extension module (.so) already imported at this point was
    # loaded during interpreter core-init, BEFORE the finder existed — which only works
    # if it was builtin/frozen. A non-empty list means that module must be made static
    # (PyImport_AppendInittab) or it will fail under modern packaging. Expected: empty.
    pre = [
        n
        for n, m in sys.modules.items()
        if getattr(m, "__file__", None) and str(m.__file__).endswith(".so")
    ]
    if pre:
        sys.stderr.write("SP_BOOTSTRAP pre-finder native modules: %r\n" % (pre,))
    for f in sys.meta_path:
        if isinstance(f, _SorefFinder):
            _installed = True
            return
    sys.meta_path.insert(0, _SorefFinder())
    _installed = True


def _patch_subinterpreters():
    """Make PEP 734 subinterpreters (Python 3.14+) able to import relocated
    native modules.

    `sys.meta_path` is *per-interpreter*: a subinterpreter created by
    `concurrent.interpreters` / `InterpreterPoolExecutor` starts with a fresh
    meta_path that does NOT contain the `_SorefFinder` installed by `_install_finder`,
    so it can import no relocated C extension (`_struct`, `_interpqueues`, ...). Since
    that machinery ships work between interpreters via pickle (`_struct`) and
    cross-interpreter queues (`_interpqueues`), the whole feature is unusable.

    Wrap `concurrent.interpreters.create()` so every new interpreter installs
    the finder before it is used. The install runs via `Interpreter.exec()` — a
    source string, which is pickle-free (unlike `Interpreter.call()`), so it
    works *before* `_struct` is importable in the child. Idempotent; a no-op
    before 3.14 (module absent) and cannot fix
    `InterpreterPoolExecutor(initializer=...)` because the initializer is
    delivered over the same broken pickle path — so it must run here, at
    creation time.

    NOTE: this relies on callers resolving `interpreters.create` as a module
    attribute at call time (as `InterpreterPoolExecutor` does on 3.14) rather
    than binding it via `from concurrent.interpreters import create`. If a
    future CPython changes that, the patch silently stops applying to the pool
    and subinterpreter imports regress — verified working on 3.14.6.
    """
    try:
        from concurrent import interpreters
    except Exception:
        return  # < 3.14, or subinterpreters unavailable
    if getattr(interpreters.create, "_sp_patched", False):
        return
    _orig_create = interpreters.create

    def create(*args, **kwargs):
        interp = _orig_create(*args, **kwargs)
        try:
            interp.exec("import _sp_bootstrap\n_sp_bootstrap.install()\n")
        except Exception as e:
            # Finder not installed in the child: it will hit the original
            # ModuleNotFoundError on its first relocated import. Leave a
            # breadcrumb (cf. the SP_BOOTSTRAP audit in `install`) instead of
            # failing `create` outright.
            sys.stderr.write("SP_BOOTSTRAP subinterpreter finder install failed: %r\n" % (e,))
        return interp

    create._sp_patched = True
    interpreters.create = create


def install():
    """Entry point called from the dart-bridge Android bootstrap.

    Installs the native-module finder in the current interpreter and — on
    3.14+ — teaches every future subinterpreter to install it too.
    Safe to call in any interpreter; idempotent.
    """
    _install_finder()
    _patch_subinterpreters()

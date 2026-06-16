"""serious_python Android import bootstrap.

Installed by the dart-bridge embedder *before* ``site`` runs, via the fixed call::

    import _sp_bootstrap; _sp_bootstrap.install()

It registers a ``sys.meta_path`` finder that resolves native CPython extension
modules which the build relocated into ``jniLibs/<abi>/`` as real ``lib<mangled>.so``
files (loaded by basename through the Android linker namespace, exactly like
``libdart_bridge.so``). Pure ``.py``/``.pyc`` modules are left to ``zipimport`` /
``FileFinder`` — this finder returns ``None`` for them.

For every relocated extension the build leaves a ``.soref`` marker at the module's
original path; its content is the ``lib<mangled>.so`` filename. The marker is read
**lazily** in ``find_spec`` via the frozen ``zipimport`` ``get_data`` API (for zip
entries) or a plain ``open`` (for entries extracted to disk, e.g. ``extract.zip``).

CRITICAL: this module must load and run *before any native module is resolvable*,
so it imports **only builtin/frozen** machinery — ``sys``, ``zipimport``,
``importlib.machinery`` — and never ``zipfile``/``struct``/``zlib`` (which would be
a chicken-and-egg: those are themselves native).
"""

import sys
import zipimport
from importlib.machinery import ExtensionFileLoader, ModuleSpec

_MARKER_SUFFIX = ".soref"
_installed = False


class _SorefFinder:
    """meta_path finder: dotted name -> jniLibs lib via its ``.soref`` marker."""

    def __init__(self):
        # Cache one zipimporter per zip sys.path entry. Value is None for entries
        # that are not zips (plain directories) so we don't retry zipimporter().
        self._zi_cache = {}

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
        """Return the soname recorded in ``member`` (.soref), or None if absent.

        Probes every current ``sys.path`` entry: zip entries via the frozen
        ``zipimport.get_data`` (known member, no native deps), directory entries
        via a plain ``open`` (covers packages unpacked from ``extract.zip``).
        """
        for entry in sys.path:
            if not entry:
                continue
            zi = self._zipimporter(entry)
            if zi is not None:
                try:
                    return zi.get_data(member)  # archive-relative member path
                except Exception:
                    continue
            else:
                # Directory entry: try the marker as a real file on disk.
                path = entry + "/" + member
                try:
                    with open(path, "rb") as f:
                        return f.read()
                except OSError:
                    continue
        return None

    def find_spec(self, fullname, path=None, target=None):
        member = fullname.replace(".", "/") + _MARKER_SUFFIX
        data = self._read_marker(member)
        if data is None:
            return None  # not a relocated native module -> let others handle it
        soname = data.decode("utf-8").strip()
        # origin = bare soname -> create_dynamic dlopen()s it by basename, which the
        # app's linker namespace resolves from the APK (modern packaging).
        loader = ExtensionFileLoader(fullname, soname)
        return ModuleSpec(fullname, loader, origin=soname)


def install():
    """Insert the finder at the front of ``sys.meta_path`` (idempotent)."""
    global _installed
    if _installed:
        return
    for f in sys.meta_path:
        if isinstance(f, _SorefFinder):
            _installed = True
            return
    sys.meta_path.insert(0, _SorefFinder())
    _installed = True

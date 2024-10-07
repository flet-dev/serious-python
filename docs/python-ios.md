# Python for iOS notes

Source: https://github.com/python/cpython/blob/main/Doc/library/importlib.rst

A specialization of :class:`importlib.machinery.ExtensionFileLoader` that
is able to load extension modules in Framework format.

For compatibility with the iOS App Store, *all* binary modules in an iOS app
must be dynamic libraries, contained in a framework with appropriate
metadata, stored in the ``Frameworks`` folder of the packaged app. There can
be only a single binary per framework, and there can be no executable binary
material outside the Frameworks folder.

To accomodate this requirement, when running on iOS, extension module
binaries are *not* packaged as ``.so`` files on ``sys.path``, but as
individual standalone frameworks. To discover those frameworks, this loader
is be registered against the ``.fwork`` file extension, with a ``.fwork``
file acting as a placeholder in the original location of the binary on
``sys.path``. The ``.fwork`` file contains the path of the actual binary in
the ``Frameworks`` folder, relative to the app bundle. To allow for
resolving a framework-packaged binary back to the original location, the
framework is expected to contain a ``.origin`` file that contains the
location of the ``.fwork`` file, relative to the app bundle.

For example, consider the case of an import ``from foo.bar import _whiz``,
where ``_whiz`` is implemented with the binary module
``sources/foo/bar/_whiz.abi3.so``, with ``sources`` being the location
registered on ``sys.path``, relative to the application bundle. This module
*must* be distributed as
``Frameworks/foo.bar._whiz.framework/foo.bar._whiz`` (creating the framework
name from the full import path of the module), with an ``Info.plist`` file
in the ``.framework`` directory identifying the binary as a framework. The
``foo.bar._whiz`` module would be represented in the original location with
a ``sources/foo/bar/_whiz.abi3.fwork`` marker file, containing the path
``Frameworks/foo.bar._whiz/foo.bar._whiz``. The framework would also contain
``Frameworks/foo.bar._whiz.framework/foo.bar._whiz.origin``, containing the
path to the ``.fwork`` file.

When a module is loaded with this loader, the ``__file__`` for the module
will report as the location of the ``.fwork`` file. This allows code to use
the ``__file__`` of a  module as an anchor for file system traveral.
However, the spec origin will reference the location of the *actual* binary
in the ``.framework`` folder.

The Xcode project building the app is responsible for converting any ``.so``
files from wherever they exist in the ``PYTHONPATH`` into frameworks in the
``Frameworks`` folder (including stripping extensions from the module file,
the addition of framework metadata, and signing the resulting framework),
and creating the ``.fwork`` and ``.origin`` files. This will usually be done
with a build step in the Xcode project; see the iOS documentation for
details on how to construct this build step.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:serious_python/src/python_versions.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'macos_utils.dart' as macos_utils;
import 'sitecustomize.dart';

const mobilePyPiUrl = "https://pypi.flet.dev";
const pyodideLockFile = "pyodide-lock.json";

const defaultSitePackagesDir = "__pypackages__";
const sitePackagesEnvironmentVariable = "SERIOUS_PYTHON_SITE_PACKAGES";
const flutterPackagesFlutterEnvironmentVariable =
    "SERIOUS_PYTHON_FLUTTER_PACKAGES";
const allowSourceDistrosEnvironmentVariable =
    "SERIOUS_PYTHON_ALLOW_SOURCE_DISTRIBUTIONS";

// Python runtime version data — `defaultPythonVersion`, `pythonReleases`, the
// `*EnvironmentVariable` names, `dartBridgeVersion`, `pythonReleaseDate` — lives
// in the generated `lib/src/python_versions.dart` (imported above). It is a
// snapshot of python-build's manifest.json; regenerate with
// `dart run serious_python:gen_version_tables`.

/// Stages the embedded Darwin (iOS/macOS) Python runtime for [shortVersion] by
/// running the plugin's version-aware prepare script through the `.pod` symlink
/// in [sitePackagesRoot]. This is what makes a version switch take effect on a
/// bare rebuild (no `pod install` re-run needed). No-op for non-Darwin platforms,
/// whose native build stages the runtime itself. Returns false if skipped. Used
/// by both the `package` and `configure` commands.
Future<bool> stageDarwinRuntime({
  required String platform,
  required String shortVersion,
  required String sitePackagesRoot,
}) async {
  final script = platform == "iOS"
      ? "prepare_ios.sh"
      : platform == "Darwin"
          ? "prepare_macos.sh"
          : null;
  if (script == null) return false;
  final release = pythonReleases[shortVersion];
  if (release == null) {
    stderr.writeln("serious_python: unknown Python version '$shortVersion'. "
        "Supported: ${pythonReleases.keys.join(", ")}");
    exit(2);
  }
  final fullVersion =
      Platform.environment[pythonFullVersionEnvironmentVariable] ??
          release.standaloneVersion;
  final buildDate = Platform.environment[pythonBuildDateEnvironmentVariable] ??
      pythonReleaseDate;
  final bridge = Platform.environment[dartBridgeVersionEnvironmentVariable] ??
      dartBridgeVersion;
  final sh = File(path.join(sitePackagesRoot, ".pod", script));
  if (!await sh.exists()) {
    stdout.writeln("serious_python: $script not found under "
        "$sitePackagesRoot/.pod — build the app once so CocoaPods creates the "
        "plugin symlink, then re-run.");
    return false;
  }
  stdout.writeln(
      "Staging $platform Python $shortVersion (CPython $fullVersion) runtime...");
  final process = await Process.start(
      "/bin/sh", [sh.path, shortVersion, fullVersion, buildDate, bridge],
      mode: ProcessStartMode.inheritStdio);
  final code = await process.exitCode;
  if (code != 0) {
    stderr.writeln("serious_python: $script failed (exit $code).");
    exit(code);
  }
  return true;
}

const platforms = {
  "iOS": {
    "iphoneos.arm64": {"tag": "ios-13.0-arm64-iphoneos", "mac_ver": ""},
    "iphonesimulator.arm64": {
      "tag": "ios-13.0-arm64-iphonesimulator",
      "mac_ver": ""
    },
    "iphonesimulator.x86_64": {
      "tag": "ios-13.0-x86_64-iphonesimulator",
      "mac_ver": ""
    }
  },
  "Android": {
    // The ABI segment uses '_' so that packaging.tags.android_platforms (3.13+
    // pip vendored packaging) — which derives the abi from
    // `sysconfig.get_platform().split("-")[-1]` — picks up the full ABI
    // (e.g. "arm64_v8a") rather than just the trailing token.
    "arm64-v8a": {"tag": "android-24-arm64_v8a", "mac_ver": ""},
    "armeabi-v7a": {"tag": "android-24-armeabi_v7a", "mac_ver": ""},
    "x86_64": {"tag": "android-24-x86_64", "mac_ver": ""},
    "x86": {"tag": "android-24-x86", "mac_ver": ""}
  },
  "Emscripten": {
    // The actual wheel platform tag is resolved per Python release from
    // `pythonReleases[...].pyodidePlatformTag` (see sitecustomize wiring
    // below) since it changes with each Pyodide ABI bump.
    "": {"tag": "", "mac_ver": ""}
  },
  "Darwin": {
    "arm64": {"tag": "", "mac_ver": "arm64"},
    "x86_64": {"tag": "", "mac_ver": "x86_64"}
  },
  "Windows": {
    "": {"tag": "", "mac_ver": ""}
  },
  "Linux": {
    "": {"tag": "", "mac_ver": ""}
  }
};

const junkFilesDesktop = [
  "**.c",
  "**.h",
  "**.cpp",
  "**.hpp",
  "**.typed",
  "**.pyi",
  "**.pxd",
  "**.pyx",
  "**.a",
  "**.pdb",
  "__pycache__",
  "**/__pycache__",
];
const junkFilesMobile = [
  ...junkFilesDesktop,
  "**.exe",
  "**.dll",
  "bin",
  "**/bin",
];

class PackageCommand extends Command {
  bool _verbose = false;
  Directory? _buildDir;
  Directory? _pythonDir;
  late String _pythonShortVersion;
  late PythonRelease _release;

  String get _pyodideRootUrl =>
      "https://cdn.jsdelivr.net/pyodide/v${_release.pyodideVersion}/full";

  /// Root of the cross-plugin download cache. Honors `FLET_CACHE_DIR` (the
  /// same env var `flet build` and the Android gradle task already use) and
  /// otherwise falls back to `~/.flet/cache` (`%USERPROFILE%\.flet\cache`
  /// on Windows). The CMake/shell plugins resolve this independently to the
  /// same path — keep the layout in sync.
  String _fletCacheRoot() {
    final env = Platform.environment['FLET_CACHE_DIR'];
    if (env != null && env.isNotEmpty) return env;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        _buildDir!.path;
    return path.join(home, '.flet', 'cache');
  }

  @override
  final name = "package";

  @override
  final description = "Packages Python app into Flutter asset.";

  PackageCommand() {
    argParser.addOption('platform',
        abbr: "p",
        allowed: ["iOS", "Android", "Emscripten", "Windows", "Linux", "Darwin"],
        mandatory: true,
        help: "Install dependencies for specific platform, e.g. 'Android'.");
    argParser.addOption('python-version',
        allowed: pythonReleases.keys.toList(),
        help: "Short Python version to bundle (e.g. 3.13). Defaults to "
            "\$$pythonVersionEnvironmentVariable env var or "
            "'$defaultPythonVersion'.");
    argParser.addMultiOption('arch',
        help:
            "Install dependencies for specific architectures only. Leave empty to install all supported architectures.");
    argParser.addMultiOption('requirements',
        abbr: "r",
        help: "The list of dependencies to install. Allows any pip options.'",
        splitCommas: false);
    argParser.addOption('asset',
        abbr: 'a',
        help:
            "Output asset path, relative to pubspec.yaml, to package Python program into.");
    argParser.addMultiOption('exclude',
        help:
            "List of relative paths to exclude from app package, e.g. \"assets,build\".");
    argParser.addFlag("skip-site-packages",
        help: "Skip installation of site packages.", negatable: false);
    argParser.addFlag("compile-app",
        help: "Compile Python application before packaging.", negatable: false);
    argParser.addFlag("compile-packages",
        help: "Compile application packages before packaging.",
        negatable: false);
    argParser.addFlag("cleanup",
        help:
            "Cleanup app and packages from unneccessary files and directories.",
        negatable: false);
    argParser.addFlag("cleanup-app",
        help: "Cleanup app from unneccessary files and directories.",
        negatable: false);
    argParser.addMultiOption('cleanup-app-files',
        help: "List of globs to delete extra app files and directories.");
    argParser.addFlag("cleanup-packages",
        help: "Cleanup packages from unneccessary files and directories.",
        negatable: false);
    argParser.addMultiOption('cleanup-package-files',
        help: "List of globs to delete extra packages files and directories.");
    argParser.addFlag("verbose", help: "Verbose output.", negatable: false);
  }

  // [run] may also return a Future.
  @override
  Future run() async {
    stdout.writeln("Running package command");
    if (argResults == null ||
        argResults?.rest == null ||
        argResults!.rest.isEmpty) {
      stdout.writeln(("Error: Source directory is not provided."));
      stdout.writeln(usage);
      exit(1);
    }

    Directory? tempDir;
    HttpServer? pyodidePyPiServer;

    try {
      final currentPath = Directory.current.path;

      // args
      String? sourceDirPath = argResults!.rest.first;
      String platform = argResults?['platform'];
      List<String> archArg = argResults?['arch'];
      List<String> requirements = argResults?['requirements'];
      String? assetPath = argResults?['asset'];
      List<String> exclude = argResults?['exclude'];
      bool skipSitePackages = argResults?["skip-site-packages"];
      bool compileApp = argResults?["compile-app"];
      bool compilePackages = argResults?["compile-packages"];
      bool cleanup = argResults?["cleanup"];
      bool cleanupApp = argResults?["cleanup-app"];
      List<String> cleanupAppFiles = argResults?['cleanup-app-files'];
      bool cleanupPackages = argResults?["cleanup-packages"];
      List<String> cleanupPackageFiles = argResults?['cleanup-package-files'];
      _verbose = argResults?["verbose"];

      _pythonShortVersion = argResults?['python-version'] ??
          Platform.environment[pythonVersionEnvironmentVariable] ??
          defaultPythonVersion;
      final baseRelease = pythonReleases[_pythonShortVersion];
      if (baseRelease == null) {
        stderr.writeln(
            "Unknown Python version: $_pythonShortVersion. Supported: ${pythonReleases.keys.join(", ")}");
        exit(2);
      }
      _release = PythonRelease(
        standaloneVersion:
            Platform.environment[pythonFullVersionEnvironmentVariable] ??
                baseRelease.standaloneVersion,
        standaloneReleaseDate:
            Platform.environment[pythonDistReleaseEnvironmentVariable] ??
                baseRelease.standaloneReleaseDate,
        pyodideVersion:
            Platform.environment[pyodideVersionEnvironmentVariable] ??
                baseRelease.pyodideVersion,
        pyodidePlatformTag: baseRelease.pyodidePlatformTag,
        prerelease: baseRelease.prerelease,
      );
      final preNote = _release.prerelease ? " — pre-release" : "";
      stdout.writeln(
          "Python $_pythonShortVersion$preNote (CPython ${_release.standaloneVersion}, "
          "Pyodide ${_release.pyodideVersion})");

      if (path.isRelative(sourceDirPath)) {
        sourceDirPath = path.join(currentPath, sourceDirPath);
      }

      final sourceDir = Directory(sourceDirPath);

      if (!platforms.containsKey(platform)) {
        stderr.writeln('Unknown platform: $platform');
        exit(2);
      }

      if (!await sourceDir.exists()) {
        stderr.writeln('Source directory does not exist.');
        exit(2);
      }

      final pubspecFile = File(path.join(currentPath, "pubspec.yaml"));
      if (!await pubspecFile.exists()) {
        stderr.writeln("Current directory must contain pubspec.yaml.");
        exit(2);
      }

      bool isMobile = (platform == "iOS" || platform == "Android");
      bool isWeb = platform == "Emscripten";

      var junkFiles = isMobile ? junkFilesMobile : junkFilesDesktop;

      // Extra indexs
      List<String> extraPyPiIndexes = [mobilePyPiUrl];
      if (platform == "Emscripten") {
        pyodidePyPiServer = await startSimpleServer();
        extraPyPiIndexes.add(
            "http://${pyodidePyPiServer.address.host}:${pyodidePyPiServer.port}/simple");
      }

      stdout.writeln("Extra PyPi indexes: $extraPyPiIndexes");

      // ensure standard Dart/Flutter "build" directory exists
      _buildDir = Directory(path.join(currentPath, "build"));
      if (!await _buildDir!.exists()) {
        await _buildDir!.create();
      }

      // asset path
      if (assetPath == null) {
        assetPath = "app/app.zip";
      } else if (assetPath.startsWith("/") || assetPath.startsWith("\\")) {
        assetPath = assetPath.substring(1);
      }

      // create dest dir
      final dest = File(path.join(currentPath, assetPath));
      if (!await dest.parent.exists()) {
        stdout.writeln("Creating asset directory: ${dest.parent.path}");
        await dest.parent.create(recursive: true);
      }

      // create temp dir
      tempDir = await Directory.systemTemp.createTemp('serious_python_temp');
      stdout.writeln("Created temp directory: ${tempDir.path}");

      // copy app to a temp dir
      stdout.writeln(
          "Copying Python app from ${sourceDir.path} to a temp directory");
      await copyDirectory(sourceDir, tempDir, sourceDir.path,
          exclude.map((s) => s.trim()).toList());

      // compile all python code
      if (compileApp) {
        stdout.writeln("Compiling Python sources in a temp directory");
        await runPython(['-m', 'compileall', '-b', tempDir.path]);

        verbose("Deleting original .py files");
        await cleanupDir(tempDir, ["**.py"]);
      }

      // cleanup
      if (cleanupApp || cleanup) {
        var allJunkFiles = [...junkFiles, ...cleanupAppFiles];
        if (_verbose) {
          verbose(
              "Delete unnecessary app files and directories: $allJunkFiles");
        } else {
          stdout.writeln(("Cleanup app"));
        }
        await cleanupDir(tempDir, allJunkFiles);
      }

      // site-packages root
      String sitePackagesRoot =
          path.join(currentPath, "build", "site-packages");
      if (Platform.environment
          .containsKey(sitePackagesEnvironmentVariable)) {
        final envValue =
            Platform.environment[sitePackagesEnvironmentVariable];
        if (envValue != null && envValue.isNotEmpty) {
          sitePackagesRoot = envValue;
        }
      }

      // install requirements
      if (requirements.isNotEmpty && !skipSitePackages) {
        if (await Directory(sitePackagesRoot).exists()) {
          await for (var f in Directory(sitePackagesRoot)
              .list()
              .where((f) => !path.basename(f.path).startsWith("."))) {
            await f.delete(recursive: true);
          }
        }

        bool flutterPackagesCopied = false;
        // invoke pip for every platform arch
        for (var arch in platforms[platform]!.entries) {
          if (archArg.isNotEmpty && !archArg.contains(arch.key)) {
            continue;
          }
          // python-build dropped 32-bit Android in 3.13 (PEP 738); the
          // platform plugin only bundles arm64-v8a + x86_64 for those
          // versions, so installing 32-bit wheels would be wasted work.
          if (platform == "Android" &&
              _pythonShortVersion != "3.12" &&
              (arch.key == "armeabi-v7a" || arch.key == "x86")) {
            continue;
          }
          String? sitePackagesDir;
          Map<String, String>? pipEnv;
          Directory? sitecustomizeDir;

          try {
            // customized pip
            // create temp dir with sitecustomize.py for mobile and web
            sitecustomizeDir = await Directory.systemTemp
                .createTemp('serious_python_sitecustomize');
            var sitecustomizePath =
                path.join(sitecustomizeDir.path, "sitecustomize.py");
            if (_verbose) {
              verbose(
                  "Configured $platform/${arch.key} platform with sitecustomize.py at $sitecustomizePath");
            } else {
              stdout.writeln(
                  "Configured $platform/${arch.key} platform with sitecustomize.py");
            }

            // Emscripten's wheel platform tag changes between Pyodide ABI
            // bumps (e.g. pyodide-2024.0 -> pyodide-2025.0 -> pyemscripten-2026.0),
            // so resolve it from the chosen Python release instead of the
            // static `platforms` map.
            final platformTag = platform == "Emscripten"
                ? _release.pyodidePlatformTag
                : arch.value["tag"]!;
            await File(sitecustomizePath).writeAsString(sitecustomizePy
                .replaceAll(
                    "{platform}", platformTag.isNotEmpty ? platform : "")
                .replaceAll("{tag}", platformTag)
                .replaceAll("{mac_ver}", arch.value["mac_ver"]!));

            // print(File(sitecustomizePath).readAsStringSync());

            pipEnv = {
              "PYTHONPATH":
                  [sitecustomizeDir.path].join(Platform.isWindows ? ";" : ":"),
              // Prevent importing user-site packages (e.g. ~/.local/.../site-packages)
              // which can shadow bundled pip in build Python.
              "PYTHONNOUSERSITE": "1",
              // Override any user-set `require-virtualenv = true` (pip.conf or
              // PIP_REQUIRE_VIRTUALENV) which otherwise aborts the install.
              "PIP_REQUIRE_VIRTUALENV": "false",
            };

            sitePackagesDir = arch.key.isNotEmpty
                ? path.join(sitePackagesRoot, arch.key)
                : sitePackagesRoot;
            if (!await Directory(sitePackagesDir).exists()) {
              await Directory(sitePackagesDir).create(recursive: true);
            }

            stdout.writeln(
                "Installing $requirements with pip command to $sitePackagesDir");

            List<String> pipArgs = ["--disable-pip-version-check"];

            if (isMobile || isWeb) {
              pipArgs.addAll(["--only-binary", ":all:"]);
              if (Platform.environment
                  .containsKey(allowSourceDistrosEnvironmentVariable)) {
                pipArgs.addAll([
                  "--no-binary",
                  Platform.environment[allowSourceDistrosEnvironmentVariable]!
                ]);
              }
            }

            for (var index in extraPyPiIndexes) {
              pipArgs.addAll(["--extra-index-url", index]);
            }

            await runPython([
              '-m',
              'pip',
              'install',
              '--upgrade',
              ...pipArgs,
              '--target',
              sitePackagesDir,
              ...requirements
            ], environment: pipEnv);

            // move $sitePackagesDir/flutter if env var is defined
            if (Platform.environment
                .containsKey(flutterPackagesFlutterEnvironmentVariable)) {
              var flutterPackagesRoot = Platform
                  .environment[flutterPackagesFlutterEnvironmentVariable];
              var flutterPackagesRootDir = Directory(flutterPackagesRoot!);
              var sitePackagesFlutterDir =
                  Directory(path.join(sitePackagesDir, "flutter"));
              if (await sitePackagesFlutterDir.exists()) {
                if (!flutterPackagesCopied) {
                  stdout.writeln(
                      "Copying Flutter packages to $flutterPackagesRoot");
                  if (!await flutterPackagesRootDir.exists()) {
                    await flutterPackagesRootDir.create(recursive: true);
                  }
                  await copyDirectory(sitePackagesFlutterDir,
                      flutterPackagesRootDir, sitePackagesFlutterDir.path, []);
                  flutterPackagesCopied = true;
                }
                await sitePackagesFlutterDir.delete(recursive: true);
              }
            }

            // compile packages
            if (compilePackages) {
              stdout.writeln("Compiling app packages at $sitePackagesDir");
              await runPython(['-m', 'compileall', '-b', sitePackagesDir]);

              verbose("Deleting original .py files");
              await cleanupDir(Directory(sitePackagesDir), ["**.py"]);
            }

            // cleanup packages
            if (cleanupPackages || cleanup) {
              var allJunkFiles = [...junkFiles, ...cleanupPackageFiles];
              if (_verbose) {
                verbose(
                    "Delete unnecessary package files and directories: $allJunkFiles");
              } else {
                stdout.writeln(("Cleanup installed packages"));
              }
              await cleanupDir(Directory(sitePackagesDir), allJunkFiles);
            }
          } finally {
            if (sitecustomizeDir != null && await sitecustomizeDir.exists()) {
              verbose(
                  "Deleting sitecustomize directory ${sitecustomizeDir.path}");
              await sitecustomizeDir.delete(recursive: true);
            }
          }
        } // for each arch

        if (platform == "Darwin") {
          await macos_utils.mergeMacOsSitePackages(
              path.join(sitePackagesRoot, "arm64"),
              path.join(sitePackagesRoot, "x86_64"),
              path.join(sitePackagesRoot),
              _verbose);
        }

        // Stage the embedded Darwin interpreter for the selected version so the
        // build uses it without `pod install` having to re-run prepare.
        await stageDarwinRuntime(
          platform: platform,
          shortVersion: _pythonShortVersion,
          sitePackagesRoot: sitePackagesRoot,
        );

        // synchronize pod
        var syncSh =
            File(path.join(sitePackagesRoot, ".pod", "sync_site_packages.sh"));
        if (await syncSh.exists()) {
          await runExec("/bin/sh", [syncSh.path]);
        }
      }

      // copy site packages to temp dir for web platform
      if (platform == "Emscripten" && requirements.isNotEmpty) {
        final sitePackagesSrcDir = Directory(sitePackagesRoot);
        if (await sitePackagesSrcDir.exists()) {
          stdout.writeln("Copying site packages to app archive");
          final webPkgDir =
              Directory(path.join(tempDir.path, defaultSitePackagesDir));
          if (!await webPkgDir.exists()) {
            await webPkgDir.create(recursive: true);
          }
          await copyDirectory(
              sitePackagesSrcDir, webPkgDir, sitePackagesSrcDir.path, []);
        }
      }

      // create archive
      stdout.writeln(
          "Creating app archive at ${dest.path} from a temp directory");
      await zipDirectoryPosix(tempDir, dest);

      // create hash file
      stdout.writeln("Writing app archive hash to ${dest.path}.hash");
      await File("${dest.path}.hash")
          .writeAsString(await calculateFileHash(dest.path));
    } catch (e) {
      stdout.writeln("Error: $e");
    } finally {
      if (tempDir != null && await tempDir.exists()) {
        stdout.writeln("Deleting temp directory");
        await tempDir.delete(recursive: true);
      }
      if (pyodidePyPiServer != null) {
        stdout.writeln("Shutting down Pyodide PyPI server");
        pyodidePyPiServer.close();
      }
    }
  }

  Future<void> copyDirectory(Directory source, Directory destination,
      String rootDir, List<String> excludeList) async {
    await for (var entity in source.list()) {
      if (excludeList.contains(path.relative(entity.path, from: rootDir))) {
        continue;
      }
      if (entity is Directory) {
        final newDirectory =
            Directory(path.join(destination.path, path.basename(entity.path)));
        await newDirectory.create();
        await copyDirectory(
            entity.absolute, newDirectory, rootDir, excludeList);
      } else if (entity is File) {
        await entity
            .copy(path.join(destination.path, path.basename(entity.path)));
      }
    }
  }

  Future<void> cleanupDir(Directory directory, List<String> filesGlobs) async {
    verbose("Cleanup directory ${directory.path}: $filesGlobs");
    await cleanupDirRecursive(
        directory,
        filesGlobs.map((g) => Glob(g.replaceAll("\\", "/"),
            context: path.Context(current: directory.path))));
  }

  Future<bool> cleanupDirRecursive(
      Directory directory, Iterable<Glob> globs) async {
    var emptyDir = true;
    for (var entity in directory.listSync()) {
      if (globs.any((g) => g.matches(entity.path.replaceAll("\\", "/"))) &&
          await entity.exists()) {
        verbose("Deleting ${entity.path}");
        await entity.delete(recursive: true);
      } else if (entity is Directory) {
        if (await cleanupDirRecursive(entity, globs)) {
          verbose("Deleting empty directory ${entity.path}");
          await entity.delete(recursive: true);
        } else {
          emptyDir = false;
        }
      } else {
        emptyDir = false;
      }
    }
    return emptyDir;
  }

  Future<int> runExec(String execPath, List<String> args,
      {Map<String, String>? environment}) async {
    final proc = await Process.start(execPath, args, environment: environment);

    await for (final line in proc.stdout.transform(utf8.decoder)) {
      verbose(line.trim());
    }

    if (await proc.exitCode != 0) {
      stderr.write(await proc.stderr.transform(utf8.decoder).join());
      exit(1);
    }
    return proc.exitCode;
  }

  Future<void> zipDirectoryPosix(Directory source, File dest) async {
    final encoder = ZipFileEncoder();
    encoder.create(dest.path);
    await for (final entity
        in source.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final relativePath = path.relative(entity.path, from: source.path);
      final posixPath = path.posix.joinAll(path.split(relativePath));
      await encoder.addFile(entity, posixPath);
    }
    await encoder.close();
  }

  Future<int> runPython(List<String> args,
      {Map<String, String>? environment}) async {
    if (_pythonDir == null) {
      _pythonDir = Directory(path.join(
          _buildDir!.path, "build_python_${_release.standaloneVersion}"));

      if (!await _pythonDir!.exists()) {
        await _pythonDir!.create();

        var isArm64 = Platform.version.contains("arm64");

        String arch = "";
        if (Platform.isMacOS && !isArm64) {
          arch = 'x86_64-apple-darwin';
        } else if (Platform.isMacOS && isArm64) {
          arch = 'aarch64-apple-darwin';
        } else if (Platform.isLinux && !isArm64) {
          arch = 'x86_64-unknown-linux-gnu';
        } else if (Platform.isLinux && isArm64) {
          arch = 'aarch64-unknown-linux-gnu';
        } else if (Platform.isWindows) {
          // python-build-standalone dropped the explicit `-shared` MSVC
          // variant; the remaining install_only_stripped build is shared.
          arch = 'x86_64-pc-windows-msvc';
        }

        var pythonArchiveFilename =
            "cpython-${_release.standaloneVersion}+${_release.standaloneReleaseDate}-$arch-install_only_stripped.tar.gz";

        // Cache CPython by release date: the same tarball is reused across
        // every example/project until `_release.standaloneReleaseDate` bumps.
        var pythonCacheDir = Directory(path.join(_fletCacheRoot(),
            'python-build-standalone', _release.standaloneReleaseDate));
        await pythonCacheDir.create(recursive: true);
        var pythonArchivePath =
            path.join(pythonCacheDir.path, pythonArchiveFilename);

        if (!await File(pythonArchivePath).exists()) {
          // download Python distr from GitHub
          final url =
              "https://github.com/astral-sh/python-build-standalone/releases/download/${_release.standaloneReleaseDate}/$pythonArchiveFilename";

          if (_verbose) {
            verbose(
                "Downloading Python distributive from $url to $pythonArchivePath");
          } else {
            stdout.writeln(
                "Downloading Python distributive from $url to $pythonArchivePath");
          }

          // Write to a .tmp sibling first so a Ctrl-C / network blip doesn't
          // poison the cache with a truncated archive on the next run.
          var tmpPath = "$pythonArchivePath.tmp";
          var response = await http.get(Uri.parse(url));
          await File(tmpPath).writeAsBytes(response.bodyBytes);
          await File(tmpPath).rename(pythonArchivePath);
        }

        // extract Python from archive
        if (_verbose) {
          verbose(
              "Extracting Python distributive from $pythonArchivePath to ${_pythonDir!.path}");
        } else {
          stdout.writeln("Extracting Python distributive");
        }

        await Process.run(
            'tar', ['-xzf', pythonArchivePath, '-C', _pythonDir!.path]);

        stdout.writeln("Python distributive extracted to ${_pythonDir!.path}");

        if (Platform.isMacOS) {
          duplicateSysconfigFile(_pythonDir!.path);
        }
      }
    }

    var pythonExePath = Platform.isWindows
        ? path.join(_pythonDir!.path, 'python', 'python.exe')
        : path.join(_pythonDir!.path, 'python', 'bin', 'python3');

    // Always log the Python command so a silent pip install (typical during
    // `pip install git+…` while git is cloning) doesn't look like a hang.
    stdout.writeln("Running: ${[pythonExePath, ...args].join(" ")}");
    return await runExec(pythonExePath, args, environment: environment);
  }

  void duplicateSysconfigFile(String pythonDir) {
    final sysConfigGlob = Glob("python/lib/python3.*/_sysconfigdata__*.py",
        context: path.Context(current: pythonDir));
    for (var sysConfig in sysConfigGlob.listSync(root: pythonDir)) {
      // copy the first found sys config and exit
      if (sysConfig is File) {
        for (final target in [
          '_sysconfigdata__darwin_arm64_iphoneos.py',
          '_sysconfigdata__darwin_arm64_iphonesimulator.py',
          '_sysconfigdata__darwin_x86_64_iphonesimulator.py',
        ]) {
          var targetPath = path.join(sysConfig.parent.path, target);
          (sysConfig as File).copySync(targetPath);
          if (_verbose) {
            verbose('Copied ${sysConfig.path} -> $targetPath');
          }
        }
        break;
      }
    }
  }

  Future<HttpServer> startSimpleServer() async {
    const htmlHeader = "<!DOCTYPE html><html><body>\n";
    const htmlFooter = "</body></html>\n";

    var pyodidePackages =
        await fetchJsonFromUrl("$_pyodideRootUrl/$pyodideLockFile");

    var wheels = Map.from(pyodidePackages["packages"])
      ..removeWhere((k, p) => !p["file_name"].endsWith(".whl"));

    Response serveRequest(Request request) {
      var path = request.url.path;
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
      var parts = path.split("/");
      if (parts.length == 1 && parts[0] == "simple") {
        return Response.ok(
            htmlHeader +
                wheels.keys
                    .map((k) => '<a href="/simple/$k/">$k</a></br>\n')
                    .join("") +
                htmlFooter,
            headers: {"Content-Type": "text/html"});
      } else if (parts.length == 2 && parts[0] == "simple") {
        List<String> links = [];
        wheels.forEach((k, p) {
          if (k == parts[1].toLowerCase()) {
            links.add(
                "<a href=\"$_pyodideRootUrl/${p['file_name']}#sha256=${p['sha256']}\">${p['file_name']}</a></br>");
          }
        });
        return Response.ok(htmlHeader + links.join("\n") + htmlFooter,
            headers: {"Content-Type": "text/html"});
      } else {
        return Response.ok('Request for "${request.url}"');
      }
    }

    var handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(serveRequest);

    var server =
        await shelf_io.serve(handler, '127.0.0.1', await getUnusedPort());

    // Enable content compression
    server.autoCompress = true;

    return server;
  }

  Future<int> getUnusedPort() {
    return ServerSocket.bind("127.0.0.1", 0).then((socket) {
      var port = socket.port;
      socket.close();
      return port;
    });
  }

  Future<Map<String, dynamic>> fetchJsonFromUrl(String url) async {
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      // Decode the JSON response
      final Map<String, dynamic> data = json.decode(response.body);
      return data;
    } else {
      throw Exception("Failed to load data from $url");
    }
  }

  Future<String> calculateFileHash(String path) async {
    final digest = sha256.convert(await File(path).readAsBytes());
    return digest.toString();
  }

  void verbose(String text) {
    if (_verbose) {
      stdout.writeln("VERBOSE: $text");
    }
  }
}

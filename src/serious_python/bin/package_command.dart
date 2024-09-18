import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'sitecustomize.dart';

const mobilePyPiUrl = "https://pypi.flet.dev/simple";
const pyodideRootUrl = "https://cdn.jsdelivr.net/pyodide/v0.26.1/full";
const pyodideLockFile = "pyodide-lock.json";

const buildPythonVersion = "3.12.6";
const buildPythonReleaseDate = "20240909";
const defaultSitePackagesDir = "__pypackages__";
const sitePackageEnvironmentVariable = "SERIOUS_PYTHON_SITE_PACKAGES";

const platformTags = {
  "iOS": {
    "ios-13.0-arm64-iphoneos": "iphoneos.arm64",
    "ios-13.0-arm64-iphonesimulator": "iphonesimulator.arm64",
    "ios-13.0-x86_64-iphonesimulator": "iphonesimulator.x86_64"
  },
  "Android": {
    "android-24-arm64-v8a": "arm64-v8a",
    "android-24-armeabi-v7a": "armeabi-v7a",
    "android-24-x86_64": "x86_64",
    "android-24-x86": "x86",
  },
  "Pyodide": {"pyodide-2024.0-wasm32": ""},
  "Windows": {"": ""},
  "Linux": {"": ""},
  "Darwin": {"": ""}
};

const junkFileExtensions = [
  ".c",
  ".h",
  ".typed",
  ".exe",
  ".a",
  ".pdb",
  ".pyd",
  ".dll"
];
const junkFilesAndDirectories = ["__pycache__", "bin"];

class PackageCommand extends Command {
  bool _verbose = false;
  Directory? _buildDir;
  Directory? _pythonDir;

  @override
  final name = "package";

  @override
  final description = "Packages Python app into Flutter asset.";

  PackageCommand() {
    argParser.addOption('platform',
        abbr: "p",
        allowed: ["iOS", "Android", "Pyodide", "Windows", "Linux", "Darwin"],
        mandatory: true,
        help:
            "Make pip to install dependencies for specific platform, e.g. 'Android'.");
    argParser.addMultiOption('requirements',
        abbr: "r",
        help:
            "Required pip dependencies in the format 'dep1,dep2==version,...'");
    argParser.addOption('asset',
        abbr: 'a',
        help:
            "Output asset path, relative to pubspec.yaml, to package Python program into.");
    argParser.addMultiOption('exclude',
        help:
            "List of relative paths to exclude from app package, e.g. \"assets,build\".");
    argParser.addFlag("compile-app",
        help: "Compile Python application before packaging.", negatable: false);
    argParser.addFlag("compile-packages",
        help: "Compile application packages before packaging.",
        negatable: false);
    argParser.addFlag("cleanup",
        help:
            "Cleanup app and packages from unneccessary files and directories.",
        negatable: false);
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
      List<String> requirements = argResults?['requirements'];
      String? assetPath = argResults?['asset'];
      List<String> exclude = argResults?['exclude'];
      bool compileApp = argResults?["compile-app"];
      bool compilePackages = argResults?["compile-packages"];
      bool cleanup = argResults?["cleanup"];
      _verbose = argResults?["verbose"];

      if (path.isRelative(sourceDirPath)) {
        sourceDirPath = path.join(currentPath, sourceDirPath);
      }

      final sourceDir = Directory(sourceDirPath);

      if (!platformTags.containsKey(platform)) {
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

      // Extra index
      String? pypiUrl;
      if (platform == "iOS" || platform == "Android") {
        pypiUrl = mobilePyPiUrl;
      } else if (platform == "Pyodide") {
        pyodidePyPiServer = await startSimpleServer();
        pypiUrl =
            "http://${pyodidePyPiServer.address.host}:${pyodidePyPiServer.port}/simple";
      }

      if (pypiUrl != null) {
        stdout.writeln("PyPi server URL: $pypiUrl");
      }

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
        await cleanupPyPackages(tempDir, [".py"], []);
      }

      // cleanup
      if (cleanup) {
        if (_verbose) {
          verbose(
              "Delete unnecessary app files with extensions: $junkFileExtensions");
          verbose(
              "Delete unnecessary app files and directories: $junkFilesAndDirectories");
        } else {
          stdout.writeln(("Cleanup app"));
        }
        await cleanupPyPackages(
            tempDir, junkFileExtensions, junkFilesAndDirectories);
      }

      // install requirements
      if (requirements.isNotEmpty) {
        // invoke pip for every platform arch
        for (var tag in platformTags[platform]!.entries) {
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
                  "Configured $platform/${tag.key} platform with sitecustomize.py at $sitecustomizePath");
            } else {
              stdout.writeln(
                  "Configured $platform/${tag.key} platform with sitecustomize.py");
            }

            await File(sitecustomizePath).writeAsString(sitecustomizePy
                .replaceAll("{platform}", tag.key.isNotEmpty ? platform : "")
                .replaceAll("{tag}", tag.key.isNotEmpty ? tag.key : ""));

            pipEnv = {
              "PYTHONPATH":
                  [sitecustomizeDir.path].join(Platform.isWindows ? ";" : ":"),
            };

            sitePackagesDir = path.join(tempDir.path, defaultSitePackagesDir);
            if (tag.value.isNotEmpty) {
              if (!Platform.environment
                  .containsKey(sitePackageEnvironmentVariable)) {
                throw "Environment variable is not set: $sitePackageEnvironmentVariable";
              }
              var sitePackagesRoot =
                  Platform.environment[sitePackageEnvironmentVariable];
              if (sitePackagesRoot!.isEmpty) {
                throw "Environment variable cannot be empty: $sitePackageEnvironmentVariable";
              }
              sitePackagesDir = path.join(sitePackagesRoot, tag.value);
            }

            if (!await Directory(sitePackagesDir).exists()) {
              await Directory(sitePackagesDir).create(recursive: true);
            }

            stdout.writeln(
                "Installing $requirements with pip command to $sitePackagesDir");

            List<String> pipArgs = [
              "--disable-pip-version-check",
              "--no-cache-dir",
              "--only-binary",
              ":all:"
            ];

            if (pypiUrl != null) {
              pipArgs.addAll(["--extra-index-url", pypiUrl]);
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

            // compile packages
            if (compilePackages) {
              stdout.writeln("Compiling app packages at $sitePackagesDir");
              await runPython(['-m', 'compileall', '-b', sitePackagesDir]);

              verbose("Deleting original .py files");
              await cleanupPyPackages(Directory(sitePackagesDir), [".py"], []);
            }

            // cleanup packages
            if (cleanup) {
              if (_verbose) {
                verbose(
                    "Delete unnecessary package files with extensions: $junkFileExtensions");
                verbose(
                    "Delete unnecessary package files and directories: $junkFilesAndDirectories");
              } else {
                stdout.writeln(("Cleanup installed packages"));
              }
              await cleanupPyPackages(Directory(sitePackagesDir),
                  junkFileExtensions, junkFilesAndDirectories);
            }
          } finally {
            if (sitecustomizeDir != null && await sitecustomizeDir.exists()) {
              verbose(
                  "Deleting sitecustomize directory ${sitecustomizeDir.path}");
              await sitecustomizeDir.delete(recursive: true);
            }
          }
        }
      }

      // create archive
      stdout.writeln(
          "Creating app archive at ${dest.path} from a temp directory");
      final encoder = ZipFileEncoder();
      encoder.zipDirectory(tempDir, filename: dest.path);

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

  Future<void> cleanupPyPackages(Directory directory,
      List<String> fileExtensions, List<String> filesAndDirectories) async {
    await for (var entity in directory.list()) {
      if (entity is Directory) {
        await cleanupPyPackages(entity, fileExtensions, filesAndDirectories);
      } else if (entity is File &&
          (fileExtensions.contains(path.extension(entity.path)) ||
              filesAndDirectories.contains(path.basename(entity.path)))) {
        verbose("Deleting ${entity.path}");

        await entity.delete();
      }
    }

    await for (var entity in directory.list()) {
      if (entity is Directory &&
          filesAndDirectories.contains(path.basename(entity.path))) {
        verbose("Deleting ${entity.path}");

        await entity.delete(recursive: true);
      }
    }
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

  Future<int> runPython(List<String> args,
      {Map<String, String>? environment}) async {
    if (_pythonDir == null) {
      _pythonDir = Directory(
          path.join(_buildDir!.path, "build_python_$buildPythonVersion"));

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
          arch = 'x86_64-pc-windows-msvc-shared';
        }

        var pythonArchiveFilename =
            "cpython-$buildPythonVersion+$buildPythonReleaseDate-$arch-install_only.tar.gz";

        var pythonArchivePath =
            path.join(_buildDir!.path, pythonArchiveFilename);

        if (!await File(pythonArchivePath).exists()) {
          // download Python distr from GitHub
          final url =
              "https://github.com/indygreg/python-build-standalone/releases/download/$buildPythonReleaseDate/$pythonArchiveFilename";

          if (_verbose) {
            verbose(
                "Downloading Python distributive from $url to $pythonArchivePath");
          } else {
            stdout.writeln(
                "Downloading Python distributive from $url to a build directory");
          }

          var response = await http.get(Uri.parse(url));
          await File(pythonArchivePath).writeAsBytes(response.bodyBytes);
        }

        // extract Python from archive
        if (_verbose) {
          "Extracting Python distributive from $pythonArchivePath to ${_pythonDir!.path}";
        } else {
          stdout.writeln("Extracting Python distributive");
        }

        await Process.run(
            'tar', ['-xzf', pythonArchivePath, '-C', _pythonDir!.path]);
      }
    }

    var pythonExePath = Platform.isWindows
        ? path.join(_pythonDir!.path, 'python', 'python.exe')
        : path.join(_pythonDir!.path, 'python', 'bin', 'python3');

    // Run the python executable
    verbose([pythonExePath, ...args].join(" "));
    return await runExec(pythonExePath, args, environment: environment);
  }

  Future<HttpServer> startSimpleServer() async {
    const htmlHeader = "<!DOCTYPE html><html><body>\n";
    const htmlFooter = "</body></html>\n";

    var pyodidePackages =
        await fetchJsonFromUrl("$pyodideRootUrl/$pyodideLockFile");

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
                "<a href=\"$pyodideRootUrl/${p['file_name']}#sha256=${p['sha256']}\">${p['file_name']}</a></br>");
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

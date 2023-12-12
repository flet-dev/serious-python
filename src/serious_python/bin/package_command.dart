import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:toml/toml.dart';

import 'sitecustomize.dart';

const desktopJunkFileExtensions = [".py", ".c", ".h", ".typed", ".exe"];
const mobileJunkFileExtensions = [
  ...desktopJunkFileExtensions,
  ".so",
  ".a",
  ".pdb",
  ".pyd",
  ".dll"
];
const webJunkFileExtensions = [
  ...desktopJunkFileExtensions,
  ".a",
  ".pdb",
  ".pyd",
  ".dll"
];
const junkFilesAndDirectories = ["__pycache__", "bin"];

class PackageCommand extends Command {
  bool _verbose = false;

  @override
  final name = "package";

  @override
  final description = "Packages Python app into Flutter asset.";

  PackageCommand() {
    argParser.addFlag("pre",
        help: "Install pre-release dependencies.", negatable: false);
    argParser.addFlag("mobile", help: "Package for mobile.", negatable: false);
    argParser.addFlag("web", help: "Package for web.", negatable: false);
    argParser.addFlag("verbose", help: "Verbose output.", negatable: false);
    argParser.addOption('asset',
        abbr: 'a',
        help:
            "Asset path, relative to pubspec.yaml, to package Python program into.");
    argParser.addOption('dep-mappings',
        help: "Pip dependency mappings in the format 'dep1>dep2,dep3>dep4'.");
    argParser.addOption('req-deps',
        help:
            "Required pip dependencies in the format 'dep1,dep2==version,...'");
    argParser.addOption('find-links',
        help: "Path or URL to HTML page with links to wheels.");
    argParser.addOption('platform',
        help:
            "Make pip to install dependencies for this platform, e.g. 'emscripten_3_1_45_wasm32'. An attempt to install native Python modules will raise an error.");
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
    Directory? sitecustomizeDir;

    try {
      final currentPath = Directory.current.path;

      // args
      String? sourceDirPath = argResults!.rest.first;
      String? assetPath = argResults?['asset'];
      bool pre = argResults?["pre"];
      bool mobile = argResults?["mobile"];
      bool web = argResults?["web"];
      String? depMappingsArg = argResults?['dep-mappings'];
      String? reqDepsArg = argResults?['req-deps'];
      String? findLinksArg = argResults?['find-links'];
      String? platformArg = argResults?['platform'];
      _verbose = argResults?["verbose"];

      if (mobile && web) {
        stderr.writeln("--mobile and --web cannot be used together.");
        exit(1);
      }

      if (path.isRelative(sourceDirPath)) {
        sourceDirPath = path.join(currentPath, sourceDirPath);
      }

      final sourceDir = Directory(sourceDirPath);

      if (!await sourceDir.exists()) {
        stderr.writeln('Source directory does not exist.');
        exit(2);
      }

      final pubspecFile = File(path.join(currentPath, "pubspec.yaml"));
      if (!await pubspecFile.exists()) {
        stderr.writeln("Current directory must contain pubspec.yaml.");
        exit(2);
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

      // copy app to a temp dir
      stdout.writeln(
          "Copying Python app from ${sourceDir.path} to ${tempDir.path}");
      await copyDirectory(sourceDir, tempDir);

      // discover dependencies
      List<String> dependencies = [];
      final requirementsFile =
          File(path.join(tempDir.path, 'requirements.txt'));
      final pyprojectFile = File(path.join(tempDir.path, 'pyproject.toml'));
      if (await requirementsFile.exists()) {
        dependencies = await requirementsFile.readAsLines();
      } else if (await pyprojectFile.exists()) {
        final content = await pyprojectFile.readAsString();
        final document = TomlDocument.parse(content).toMap();
        var depSection = findTomlDependencies(document);
        if (depSection != null) {
          if (depSection is List) {
            dependencies = depSection.map((e) => e.toString()).toList();
          } else {
            stdout.writeln(
                "Warning: [dependencies] section of map type is not yet supported.");
            // dependencies = List<String>.from(
            //     depSection.keys.map((key) => '$key=${depSection[key]}'));
          }
        }
      }

      // apply dependency mappings
      if (depMappingsArg != null) {
        for (var depMappingPair
            in depMappingsArg.split(",").map((s) => s.trim())) {
          List<String> mapping =
              depMappingPair.split(">").map((s) => s.trim()).toList();
          if (mapping.length != 2) {
            stderr.writeln("Invalid dependency mapping: $depMappingPair");
            exit(3);
          }
          dependencies = dependencies
              .map((d) => d.replaceAllMapped(RegExp(mapping[0] + r'(\W{1,}|$)'),
                  (match) => '${mapping[1]}${match.group(1)}'))
              .toList();
        }
      }

      // add extra dependencies
      var depNameRe = RegExp(r'([A-Za-z0-9_-]+)(\W{1,}|$)');
      if (reqDepsArg != null) {
        for (var reqDep in reqDepsArg.split(",").map((s) => s.trim())) {
          var depName = depNameRe.allMatches(reqDep).firstOrNull?.group(1);
          if (depName == null) {
            stderr.writeln("Invalid required dependency: $reqDep");
            exit(4);
          }
          if (!dependencies
              .any((s) => RegExp(depName + r'(\W{1,}|$)').hasMatch(s))) {
            dependencies.add(reqDep);
          }
        }
      }

      List<String> extraArgs = [];
      if (pre) {
        extraArgs.add("--pre");
      }

      if (platformArg != null) {
        // create temp dir with sitecustomize.py
        sitecustomizeDir = await Directory.systemTemp
            .createTemp('serious_python_sitecustomize');
        var sitecustomizePath =
            path.join(sitecustomizeDir.path, "sitecustomize.py");
        stdout.writeln(
            "Configured $platformArg platform with sitecustomize.py at $sitecustomizePath");
        await File(sitecustomizePath).writeAsString(
            sitecustomizePy.replaceAll('"emscripten"', '"$platformArg"'));
      }

      var pipEnvVars = {
        "CC": "/bin/false",
        "CXX": "/bin/false",
        "PYTHONPATH": [tempDir.path, sitecustomizeDir?.path]
            .where((e) => e != null)
            .join(Platform.isWindows ? ";" : ":"),
      };

      var pyPackagesDir = path.join(tempDir.path, '__pypackages__');

      if (findLinksArg != null) {
        var findLinksPath = findLinksArg;
        if (path.isRelative(findLinksPath)) {
          findLinksPath = path.join(currentPath, findLinksPath);
        }
        var findLinksFile = File(findLinksPath);
        if (!await findLinksFile.exists()) {
          stderr.writeln('--find-links file does not exist.');
          exit(2);
        }
        var findLinks = await findLinksFile.readAsString();
        List<String> findLinkDependencies = [];
        for (var dep in dependencies.toList()) {
          var depName =
              depNameRe.allMatches(dep).firstOrNull?.group(1)?.toLowerCase();
          if (depName == null) {
            stderr.writeln("Invalid dependency: $dep");
            exit(4);
          }
          if (findLinks.contains(">$depName-")) {
            findLinkDependencies.add(dep);
            dependencies.remove(dep);
          }
        }

        if (findLinkDependencies.isNotEmpty) {
          stdout.writeln(
              "Installing 'find-links' dependencies $findLinkDependencies with pip command to $pyPackagesDir");

          await runPython([
            '-m',
            'pip',
            'install',
            '--isolated',
            '--upgrade',
            ...extraArgs,
            '--target',
            pyPackagesDir,
            '--no-index',
            '--find-links',
            findLinksPath,
            ...findLinkDependencies
          ], environment: pipEnvVars);
        }
      } // --find-links

      if (dependencies.isNotEmpty) {
        stdout.writeln(
            "Installing dependencies $dependencies with pip command to $pyPackagesDir");

        await runPython([
          '-m',
          'pip',
          'install',
          '--isolated',
          '--upgrade',
          ...extraArgs,
          '--target',
          pyPackagesDir,
          ...dependencies
        ], environment: pipEnvVars);
      }

      // compile all python code
      stdout.writeln("Compiling Python sources at ${tempDir.path}");
      await runPython(['-m', 'compileall', '-b', tempDir.path]);

      List<String> fileExtensions = mobile
          ? mobileJunkFileExtensions
          : (web ? webJunkFileExtensions : desktopJunkFileExtensions);

      // remove unnecessary files
      stdout
          .writeln("Delete unnecessary files with extensions: $fileExtensions");
      stdout.writeln(
          "Delete unnecessary files and directories: $junkFilesAndDirectories");
      await cleanupPyPackages(tempDir, fileExtensions, junkFilesAndDirectories);

      // create archive
      stdout
          .writeln("Creating app archive at ${dest.path} from ${tempDir.path}");
      final encoder = ZipFileEncoder();
      encoder.zipDirectory(tempDir, filename: dest.path);
    } catch (e) {
      stdout.writeln("Error: $e");
    } finally {
      if (tempDir != null && await tempDir.exists()) {
        stdout.writeln("Deleting temp directory ${tempDir.path}");
        await tempDir.delete(recursive: true);
      }
      if (sitecustomizeDir != null && await sitecustomizeDir.exists()) {
        stdout.writeln(
            "Deleting sitecustomize directory ${sitecustomizeDir.path}");
        await sitecustomizeDir.delete(recursive: true);
      }
    }
  }

  dynamic findTomlDependencies(Map<String, dynamic> section) {
    if (section.containsKey('dependencies')) {
      return section['dependencies'];
    }

    for (final value in section.values) {
      if (value is Map<String, dynamic>) {
        final dependencies = findTomlDependencies(value);
        if (dependencies != null) {
          return dependencies;
        }
      }
    }

    return null;
  }

  Future<void> copyDirectory(Directory source, Directory destination) async {
    await for (var entity in source.list()) {
      if (entity is Directory) {
        final newDirectory =
            Directory(path.join(destination.path, path.basename(entity.path)));
        await newDirectory.create();
        await copyDirectory(entity.absolute, newDirectory);
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
    var pythonDir =
        Directory(path.join(Directory.systemTemp.path, "hostpython3.11"));

    var pythonExePath = Platform.isWindows
        ? path.join(pythonDir.path, 'python', 'python.exe')
        : path.join(pythonDir.path, 'python', 'bin', 'python3');

    if (!await File(pythonExePath).exists()) {
      stdout
          .writeln("Downloading and extracting Python into ${pythonDir.path}");

      if (await pythonDir.exists()) {
        await pythonDir.delete(recursive: true);
      }
      await pythonDir.create(recursive: true);

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

      final url =
          "https://github.com/indygreg/python-build-standalone/releases/download/20231002/cpython-3.11.6+20231002-$arch-install_only.tar.gz";

      // Download the release asset
      var response = await http.get(Uri.parse(url));
      var archivePath = path.join(pythonDir.path, 'python.tar.gz');
      await File(archivePath).writeAsBytes(response.bodyBytes);

      // Extract the archive
      await Process.run('tar', ['-xzf', archivePath, '-C', pythonDir.path]);
    } else {
      verbose("Python executable found at $pythonExePath");
    }

    // Run the python executable
    verbose([pythonExePath, ...args].join(" "));
    return await runExec(pythonExePath, args, environment: environment);
  }

  void verbose(String text) {
    if (_verbose) {
      stdout.writeln("VERBOSE: $text");
    }
  }
}

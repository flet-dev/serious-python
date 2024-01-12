import 'dart:io';

import 'package:flet/flet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:serious_python/serious_python.dart';
import 'package:url_strategy/url_strategy.dart';

const bool isProduction = bool.fromEnvironment('dart.vm.product');

const assetPath = "app/app.zip";
const pythonModuleName = "main"; // {{ cookiecutter.python_module_name }}
final hideLoadingPage =
    bool.tryParse("{{ cookiecutter.hide_loading_animation }}".toLowerCase()) ??
        true;
final windowsTcpPort =
    int.tryParse("{{ cookiecutter.windows_tcp_port }}") ?? 63777;

const pythonScript = """
import traceback, sys

print("This is script!!!")

try:
    import {module_name}
except Exception as e:
    traceback.print_exception(e)
""";

// global vars
String pageUrl = "";
String assetsDir = "";
String appDir = "";
Map<String, String> environmentVariables = {};

void main() async {
  if (isProduction) {
    // ignore: avoid_returning_null_for_void
    debugPrint = (String? message, {int? wrapWidth}) => null;
  }

  runApp(FutureBuilder(
      future: prepareApp(),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.hasData) {
          // OK - start Python program
          return kIsWeb
              ? FletApp(
                  pageUrl: pageUrl,
                  assetsDir: assetsDir,
                  hideLoadingPage: hideLoadingPage,
                )
              : FutureBuilder(
                  future: runPythonApp(),
                  builder:
                      (BuildContext context, AsyncSnapshot<String?> snapshot) {
                    if (snapshot.hasData || snapshot.hasError) {
                      // error or premature finish
                      return ErrorScreen(
                          title: "Error running app",
                          text: snapshot.data ?? snapshot.error.toString());
                    } else {
                      // no result of error
                      return FletApp(
                        pageUrl: pageUrl,
                        assetsDir: assetsDir,
                        hideLoadingPage: hideLoadingPage,
                      );
                    }
                  });
        } else if (snapshot.hasError) {
          // error
          return ErrorScreen(
              title: "Error starting app", text: snapshot.error.toString());
        } else {
          // loading
          return const BlankScreen();
        }
      }));
}

Future prepareApp() async {
  if (kIsWeb) {
    // web mode - connect via HTTP
    pageUrl = Uri.base.toString();
    var routeUrlStrategy = getFletRouteUrlStrategy();
    if (routeUrlStrategy == "path") {
      setPathUrlStrategy();
    }
  } else {
    await setupDesktop();

    // extract app from asset
    appDir = await extractAssetZip(assetPath);

    // set current directory to app path
    Directory.current = appDir;

    assetsDir = path.join(appDir, "assets");

    environmentVariables["FLET_PLATFORM"] =
        defaultTargetPlatform.name.toLowerCase();

    if (defaultTargetPlatform == TargetPlatform.windows) {
      // use TCP on Windows
      pageUrl = "tcp://localhost:$windowsTcpPort";
      environmentVariables["FLET_SERVER_PORT"] = windowsTcpPort.toString();
    } else {
      // use UDS on other platforms
      pageUrl = "flet.sock";
      environmentVariables["FLET_SERVER_UDS_PATH"] = pageUrl;
    }
  }

  return "";
}

Future<String?> runPythonApp() async {
  var script = pythonScript.replaceAll('{module_name}', pythonModuleName);

  // start socket server - TODO

  // run python async
  SeriousPython.runProgram(path.join(appDir, "$pythonModuleName.pyc"),
      script: script, environmentVariables: environmentVariables);

  // wait for client connection to close
  // TODO
  return null;
}

class ErrorScreen extends StatelessWidget {
  final String title;
  final String text;

  const ErrorScreen({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
            child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SelectableText(text, style: Theme.of(context).textTheme.bodySmall)
            ],
          ),
        )),
      ),
    );
  }
}

class BlankScreen extends StatelessWidget {
  const BlankScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: SizedBox.shrink(),
      ),
    );
  }
}

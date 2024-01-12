import 'dart:async';
import 'dart:io';

import 'package:flet/flet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
final windowsStdoutTcpPort =
    int.tryParse("{{ cookiecutter.windows_tcp_port }}") ?? 63778;

const pythonScript = """
import os, socket, sys, traceback

class SocketWriter:
    def __init__(self, socket):
        self.socket = socket

    def write(self, message):
        self.socket.sendall(message.encode())

    def flush(self):
        pass

stdout_socket_addr = os.environ.get("FLET_PYTHON_OUTPUT_SOCKET_ADDR")
stdout_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
stdout_socket.connect(stdout_socket_addr)

sys.stdout = sys.stderr =SocketWriter(stdout_socket)

print("This is script!!!")

try:
    import {module_name}
except Exception as e:
    traceback.print_exception(e)

stdout_socket.close()
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
                      return MaterialApp(
                        home: ErrorScreen(
                            title: "Error running app",
                            text: snapshot.data ?? snapshot.error.toString()),
                      );
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
          return MaterialApp(
              home: ErrorScreen(
                  title: "Error starting app",
                  text: snapshot.error.toString()));
        } else {
          // loading
          return const MaterialApp(home: BlankScreen());
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

  var completer = Completer<String>();

  ServerSocket outSocketServer;
  String socketAddr = "";
  StringBuffer stdout = StringBuffer();

  if (defaultTargetPlatform == TargetPlatform.windows) {
    var tcpAddr = "127.0.0.1";
    var tcpPort = windowsStdoutTcpPort;
    outSocketServer = await ServerSocket.bind(tcpAddr, tcpPort);
    debugPrint(
        'Python output TCP Server is listening on port ${outSocketServer.port}');
    socketAddr = "$tcpAddr:$tcpPort";
  } else {
    socketAddr = "stdout.sock";
    outSocketServer = await ServerSocket.bind(
        InternetAddress(socketAddr, type: InternetAddressType.unix), 0);
    debugPrint('Python output Socket Server is listening on $socketAddr');
  }

  environmentVariables["FLET_PYTHON_OUTPUT_SOCKET_ADDR"] = socketAddr;

  void closeOutServer() {
    outSocketServer.close();
    completer.complete(stdout.toString());
  }

  outSocketServer.listen((client) {
    debugPrint(
        'Connection from: ${client.remoteAddress.address}:${client.remotePort}');
    client.listen((data) {
      var s = String.fromCharCodes(data);
      stdout.write(s);
    }, onError: (error) {
      client.close();
      closeOutServer();
    }, onDone: () {
      client.close();
      closeOutServer();
    });
  });

  // run python async
  SeriousPython.runProgram(path.join(appDir, "$pythonModuleName.pyc"),
      script: script, environmentVariables: environmentVariables);

  // wait for client connection to close
  return completer.future;
}

class ErrorScreen extends StatelessWidget {
  final String title;
  final String text;

  const ErrorScreen({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
          child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                  child: const Icon(
                    Icons.copy,
                    size: 16,
                  ),
                )
              ],
            ),
            Expanded(
                child: SingleChildScrollView(
              child: SelectableText(text,
                  style: Theme.of(context).textTheme.bodySmall),
            ))
          ],
        ),
      )),
    );
  }
}

class BlankScreen extends StatelessWidget {
  const BlankScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SizedBox.shrink(),
    );
  }
}

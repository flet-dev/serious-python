import 'dart:io';

import 'package:flet/flet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:serious_python/serious_python.dart';

void main() async {
  await setupDesktop();

  // extract app from asset
  var appDir = await extractAssetZip("app/app.zip");

  // set current directory to app path
  Directory.current = appDir;

  String pageUrl = "";

  var environmentVariables = {
    "FLET_PLATFORM": defaultTargetPlatform.name.toLowerCase()
  };

  if (defaultTargetPlatform == TargetPlatform.windows) {
    // use TCP on Windows
    //var port = await getUnusedPort();
    var port = 63777;
    pageUrl = "tcp://localhost:$port";
    environmentVariables["FLET_SERVER_PORT"] = port.toString();
  } else {
    // use UDS on other platforms
    pageUrl = "flet.sock";
    environmentVariables["FLET_SERVER_UDS_PATH"] = pageUrl;
  }

  SeriousPython.runProgram(path.join(appDir, "main.pyc"),
          environmentVariables: environmentVariables)
      .then((result) => debugPrint("Python program running result: $result"));

  runApp(FletApp(
    pageUrl: pageUrl,
    assetsDir: path.join(appDir, "assets"),
    hideLoadingPage: true,
  ));
}

// Calling this method causes Windows firewall dialog to popup
Future<int> getUnusedPort() {
  return ServerSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
    var port = socket.port;
    socket.close();
    return port;
  });
}

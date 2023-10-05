import 'dart:io';

import 'package:flet/flet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:serious_python/serious_python.dart';

void main() async {
  const sockName = "flet.sock";

  await setupDesktop();

  var fletPlatform = "";
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    fletPlatform = "iOS";
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    fletPlatform = "Android";
  } else if (defaultTargetPlatform == TargetPlatform.macOS) {
    fletPlatform = "Android";
  }

  // extract app from asset
  var appDir = await extractAssetZip("app/app.zip");

  // set current directory to app path
  Directory.current = appDir;

  SeriousPython.runProgram(path.join(appDir, "main.pyc"),
      environmentVariables: {
        "FLET_PLATFORM": fletPlatform,
        "FLET_SERVER_UDS_PATH": sockName
      });

  runApp(FletApp(
    pageUrl: sockName,
    assetsDir: path.join(appDir, "assets"),
  ));
}

import 'package:flet/flet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:serious_python/serious_python.dart';

void main() async {
  var fletPlatform = "";
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    fletPlatform = "iOS";
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    fletPlatform = "Android";
  }
  SeriousPython().run("app/app.zip",
      appFileName: "counter.py",
      environmentVariables: {
        "FLET_PLATFORM": fletPlatform,
        "FLET_SERVER_UDS_PATH": "flet.sock"
      });
  runApp(const FletApp(
    pageUrl: "flet.sock",
    assetsDir: "",
  ));
}

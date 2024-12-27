import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:run_example/utils.dart';
import 'package:serious_python/serious_python.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _pyResult = "Running...";

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String? pyResult;

    Directory tempDir =
        await (await getTemporaryDirectory()).createTemp("run_example");

    String resultFileName = p.join(tempDir.path, "out.txt");
    String resultValue = getRandomString(20);

    await SeriousPython.run("app/app.zip",
            environmentVariables: {
              "RESULT_FILENAME": resultFileName,
              "RESULT_VALUE": resultValue
            },
            sync: false)
        .then((result) => pyResult = result);

    // try reading out.txt in a loop
    var i = 10;
    while (i-- > 0) {
      var out = File(resultFileName);
      if (await out.exists()) {
        var r = await out.readAsString();
        pyResult = (r == resultValue) ? "PASS" : r;
        break;
      } else {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _pyResult = pyResult ?? "TIMEOUT";
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Serious Python example app'),
        ),
        body: Center(
          child: SelectableText(_pyResult),
        ),
      ),
    );
  }
}

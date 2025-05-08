import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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

    // ProcessSignal.sigint.watch().listen((signal) {
    //   print('🚨 SIGINT received — triggering shutdown...');
    //   String message = "\$shutdown";
    //   final Pointer<Char> ptr = message.toNativeUtf8().cast<Char>();
    //   enqueueMessageFromDart(ptr, message.length);
    //   calloc.free(ptr);
    //   exit(0);
    // });

    // Set up ReceivePort
    final receivePort = ReceivePort();
    receivePort.listen((message) {
      if (message is Uint8List) {
        print('📥 Received message: ${String.fromCharCodes(message)}');
      } else {
        print('⚠️ Unexpected message type: $message');
      }
    });

    SeriousPython.run("app/app.zip",
            environmentVariables: {
              "RESULT_FILENAME": resultFileName,
              "RESULT_VALUE": resultValue
            },
            sync: false,
            sendPort: receivePort.sendPort)
        .then((result) => pyResult = result);

    await Future.delayed(const Duration(seconds: 1));

    for (int i = 0; i < 10; i++) {
      if (i == 0) print("🧪 Sending first message from Dart...");
      String message = "aaa bbb ccc $i";
      Uint8List bytes = Uint8List.fromList(utf8.encode(message));

      SeriousPython.sendMessageToPython(bytes);

      print("After calling enqueueMessageFromDart: $i");
      await Future.delayed(const Duration(milliseconds: 1));
    }

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

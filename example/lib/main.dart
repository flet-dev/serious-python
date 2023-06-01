import 'package:flutter/material.dart';
import 'package:serious_python/serious_python.dart';

void main() {
  startPythonProgram();
  runApp(const MyApp());
}

void startPythonProgram() async {
  debugPrint("startPythonProgram()");
  WidgetsFlutterBinding.ensureInitialized();

  var python = SeriousPython();
  python.run("app/main.py",
      modulePaths: ["main"], environmentVariables: {"a": "1", "b": "2"});
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: const Center(
          child: Text('Hello!'),
        ),
      ),
    );
  }
}

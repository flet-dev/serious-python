import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:serious_python/serious_python.dart';

void main() {
  startPythonProgram();
  runApp(const MyApp());
}

void startPythonProgram() async {
  debugPrint("startPythonProgram()");
  WidgetsFlutterBinding.ensureInitialized();

  var python = SeriousPython();
  python.run("app/Archive.zip",
      modulePaths: ["main"], environmentVariables: {"a": "1", "b": "2"});
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? _result;

  @override
  void initState() {
    super.initState();
    getServiceResult();
  }

  Future getServiceResult() async {
    while (true) {
      try {
        var response = await http.get(Uri.parse("http://localhost:8000"));
        setState(() {
          _result = response.body;
        });
        return;
      } catch (_) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget? child;
    if (_result != null) {
      child = Text(_result!);
    } else {
      child = const CircularProgressIndicator();
    }

    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(
            title: const Text('Plugin example app'),
          ),
          body: Column(children: [
            Expanded(
              child: Center(
                child: child,
              ),
            ),
            Row(
              children: [
                Expanded(
                    child: TextFormField(
                  keyboardType: TextInputType.multiline,
                  minLines: 1,
                  maxLines: 10,
                )),
                ElevatedButton(onPressed: () {}, child: const Text("Run"))
              ],
            )
          ])),
    );
  }
}

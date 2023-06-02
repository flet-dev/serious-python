import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:serious_python/serious_python.dart';

void main() {
  startPython();
  runApp(const MyApp());
}

void startPython() async {
  SeriousPython().run("app/Archive.zip",
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
        await Future.delayed(const Duration(milliseconds: 200));
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
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
          appBar: AppBar(
            title: const Text('Python REPL'),
          ),
          body: SafeArea(
              child: Column(children: [
            Expanded(
              child: Center(
                child: child,
              ),
            ),
            Container(
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  Expanded(
                      child: TextFormField(
                    keyboardType: TextInputType.multiline,
                    minLines: 1,
                    maxLines: 10,
                  )),
                  ElevatedButton(onPressed: () {}, child: const Text("Run"))
                ],
              ),
            )
          ]))),
    );
  }
}

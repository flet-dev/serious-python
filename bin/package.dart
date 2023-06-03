import 'dart:io';

import 'package:args/args.dart';

void main(List<String> args) {
  stdout.writeln("Hello from command line");
  // Parsing arguments
  final parser = ArgParser();
  parser.addOption("src");
  parser.addFlag("help", abbr: "h");
  parser.addFlag('emojis', abbr: 'e', negatable: false);
  final argResults = parser.parse(args);
  if (argResults["help"]) {
    stdout.writeln(("Usage:"));
    exit(0);
  }
  var srcDir = argResults["src"];
  stdout.writeln("Source dir: $srcDir");

  // installing python modules
  // pip install --isolated --upgrade --target /path/to/__pypackages__ -r ___requirements.txt
  /*
        "CC": "/bin/false",
        "CXX": "/bin/false",
        "PYTHONPATH": ctx.site_packages_dir,
        "PYTHONOPTIMIZE": "2",

    After installation:
    - remove all *.so, *.a files
    - remove all __pycache__ dirs
    - remove "bin" directory
  */
}

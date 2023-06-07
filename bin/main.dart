import 'package:args/command_runner.dart';

import 'package_command.dart';

void main(List<String> arguments) async {
  var runner = CommandRunner("dart run serious_python:main",
      "A tool for packaging Python apps to work with serious_python package.")
    ..addCommand(PackageCommand());

  await runner.run(arguments);
}

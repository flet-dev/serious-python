import 'dart:io';

import '../../bin/package_command.dart';

/// Runs the command given as arguments through `PackageCommand.runExec` and
/// prints the status it returns. `runExec` exits the process when the command
/// fails, so tests run this program in its own process.
Future<void> main(List<String> args) async {
  final status = await PackageCommand().runExec(args.first, args.sublist(1));
  stdout.writeln("runExec returned $status");
}

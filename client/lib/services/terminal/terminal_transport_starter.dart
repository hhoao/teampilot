import 'dart:async';

import 'package:flutter_pty/flutter_pty.dart';

import '../cli/cli_tool_locator.dart';
import '../../utils/logger.dart';
import 'local_pty_transport.dart';
import 'terminal_transport.dart';

typedef TransportStarter =
    Future<TerminalTransport> Function(
      String executable, {
      required List<String> arguments,
      required String workingDirectory,
      required int columns,
      required int rows,
      Map<String, String>? environment,
    });

Future<TerminalTransport> defaultTransportStarter(
  String executable, {
  required List<String> arguments,
  required String workingDirectory,
  required int columns,
  required int rows,
  Map<String, String>? environment,
}) async {
  final spawnExecutable = CliToolLocator.resolveSpawnExecutable(executable);
  final pty = Pty.start(
    spawnExecutable,
    arguments: arguments,
    workingDirectory: workingDirectory,
    columns: columns,
    rows: rows,
    environment: environment,
  );
  appLogger.d('Pty started');
  return LocalPtyTransport(pty);
}

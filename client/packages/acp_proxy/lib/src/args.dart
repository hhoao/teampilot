import 'dart:io';

import 'idle_policy.dart';

/// Parsed `teampilot-acp-proxy` arguments. Parsing does not touch the disk.
class AcpProxyArgs {
  const AcpProxyArgs({
    required this.root,
    required this.idleTimeout,
    required this.detach,
    required this.cliIds,
  });

  final Directory root;
  final Duration idleTimeout;
  final bool detach;
  final List<String> cliIds;
}

/// Reads `--root`, `--idle-timeout` (`30m`), repeated `--cli`, and `--detach`.
///
/// Missing `--root` throws [FormatException]. `--detach` only sets the flag.
AcpProxyArgs parseAcpProxyArgs(List<String> args) {
  String? root;
  var idleTimeout = acpProxyIdleTimeout;
  var detach = false;
  final cliIds = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--root':
        root = _value(args, ++i, '--root');
      case '--idle-timeout':
        idleTimeout = _idleTimeout(_value(args, ++i, '--idle-timeout'));
      case '--cli':
        cliIds.add(_value(args, ++i, '--cli'));
      case '--detach':
        detach = true;
      default:
        throw FormatException('unknown argument: $arg');
    }
  }
  if (root == null || root.isEmpty) {
    throw const FormatException('missing --root');
  }
  return AcpProxyArgs(
    root: Directory(root),
    idleTimeout: idleTimeout,
    detach: detach,
    cliIds: List<String>.unmodifiable(cliIds),
  );
}

String _value(List<String> args, int index, String flag) {
  if (index >= args.length || args[index].isEmpty) {
    throw FormatException('$flag needs a value');
  }
  return args[index];
}

/// Arguments for the detached child process.
///
/// When [scriptPath] is the compiled executable, the child receives only
/// [args] without `--detach`. A `dart` script path is different, so the
/// child also receives [executableArguments] and [scriptPath].
List<String> acpProxyDetachArguments({
  required List<String> executableArguments,
  required String scriptPath,
  required String executable,
  required List<String> args,
}) {
  final userArgs = [
    for (final arg in args)
      if (arg != '--detach') arg,
  ];
  if (scriptPath == executable) return userArgs;
  return [...executableArguments, scriptPath, ...userArgs];
}

/// Minutes only, matching `--idle-timeout 30m`.
Duration _idleTimeout(String raw) {
  final match = RegExp(r'^(\d+)m$').firstMatch(raw);
  if (match == null) {
    throw FormatException('invalid --idle-timeout: $raw');
  }
  return Duration(minutes: int.parse(match.group(1)!));
}

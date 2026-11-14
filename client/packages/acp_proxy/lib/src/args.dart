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

/// Minutes only, matching `--idle-timeout 30m`.
Duration _idleTimeout(String raw) {
  final match = RegExp(r'^(\d+)m$').firstMatch(raw);
  if (match == null) {
    throw FormatException('invalid --idle-timeout: $raw');
  }
  return Duration(minutes: int.parse(match.group(1)!));
}

import 'dart:convert';

import '../../io/filesystem.dart';

/// Runs a command on the remote host and returns trimmed stdout (empty when the
/// command is not found / fails). Injected so provisioning is testable.
typedef RemoteCommandRunner = Future<String> Function(String command);

/// The argv a long-blocking remote member's MCP config invokes: a stdio↔TCP
/// relay that first writes the bus handshake frame, then pipes the CLI's MCP
/// traffic to the reverse-tunnel loopback port.
class RelayPlan {
  const RelayPlan({required this.argv, required this.kind});

  final List<String> argv;

  /// Diagnostic: which relay strategy was chosen.
  final RelayKind kind;
}

enum RelayKind { socat, nc, bundledStatic }

/// Thrown when no relay can be provisioned on the remote host for [arch].
class RelayUnavailableException implements Exception {
  RelayUnavailableException(this.arch);
  final String arch;
  @override
  String toString() =>
      'No relay available on the remote host (no socat/nc, no bundled static '
      'relay for arch "$arch"). Cannot connect the remote member to the bus.';
}

/// Layered relay provisioning (P3b, POSIX/linux only this round):
/// 1. prefer remote `socat` (zero distribution),
/// 2. else remote `nc`,
/// 3. else materialize a bundled static relay for the remote arch
///    (linux-x64 / linux-arm64),
/// 4. else throw [RelayUnavailableException].
class RelayProvisioner {
  const RelayProvisioner();

  /// Directory on the remote host where a bundled relay is materialized.
  static const bundledRelayDir = '.flashskyai/relay';

  Future<RelayPlan> provision({
    required Filesystem remoteFs,
    required RemoteCommandRunner run,
    required int tunnelPort,
    required String token,
    required String memberId,
    required String arch,
  }) async {
    final handshake = jsonEncode({'token': token, 'memberId': memberId});

    final socat = (await run('command -v socat')).trim();
    if (socat.isNotEmpty) {
      return RelayPlan(
        kind: RelayKind.socat,
        argv: _pipeWithHandshake(
          handshake: handshake,
          pipeCommand: '$socat - TCP:127.0.0.1:$tunnelPort',
        ),
      );
    }

    final nc = (await run('command -v nc')).trim();
    if (nc.isNotEmpty) {
      return RelayPlan(
        kind: RelayKind.nc,
        argv: _pipeWithHandshake(
          handshake: handshake,
          pipeCommand: '$nc 127.0.0.1 $tunnelPort',
        ),
      );
    }

    final bundled = await _materializeBundledRelay(remoteFs, arch);
    if (bundled != null) {
      return RelayPlan(
        kind: RelayKind.bundledStatic,
        argv: [bundled, '127.0.0.1', '$tunnelPort', '--token', token, '--member', memberId],
      );
    }

    throw RelayUnavailableException(arch);
  }

  /// Shell wrapper: emit the handshake line, then bidirectionally pipe the CLI's
  /// stdio MCP traffic through [pipeCommand]. Works with socat/nc which cannot
  /// inject an initial frame themselves.
  List<String> _pipeWithHandshake({
    required String handshake,
    required String pipeCommand,
  }) {
    // single-quote the handshake for the shell; it is JSON (no single quotes).
    return [
      'sh',
      '-c',
      "{ printf '%s\\n' '$handshake'; cat; } | $pipeCommand",
    ];
  }

  /// Materializes the bundled static relay for [arch] under [bundledRelayDir].
  /// This round only `linux-x64` / `linux-arm64` are supported; the binary asset
  /// itself ships with the app bundle (placeholder until packaged — see plan
  /// §5/Task 7). Returns the remote path, or null when [arch] is unsupported.
  Future<String?> _materializeBundledRelay(Filesystem fs, String arch) async {
    const supported = {'linux-x64', 'linux-arm64'};
    if (!supported.contains(arch)) return null;
    final dir = bundledRelayDir;
    final path = fs.pathContext.join(dir, 'flashskyai-bus-relay-$arch');
    await fs.ensureDir(dir);
    // The real static binary is materialized from the app bundle here. Until the
    // binary is packaged, the path is reserved so the wiring + selection are
    // exercised; a missing binary surfaces at exec time, not silently.
    return path;
  }
}

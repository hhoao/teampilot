import 'dart:convert';

import '../../../models/runtime_target.dart';
import '../../io/filesystem.dart';

/// Runs a command on the remote host and returns trimmed stdout (empty when the
/// command is not found / fails). Injected so provisioning is testable.
typedef RemoteCommandRunner = Future<String> Function(String command);

/// Resolves the bytes of a bundled static relay binary by asset name
/// (`flashskyai-bus-relay-<arch>` or `…-windows-x64.exe`). Returns null when the
/// binary is not packaged in this build — provisioning then fails with a clear
/// [RelayAssetMissingException] instead of installing a non-existent file.
///
/// Injected so relay selection/materialization is fully unit-testable without a
/// real packaged binary (the default resolver always reports "missing").
typedef RelayAssetResolver = Future<List<int>?> Function(String assetName);

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
  RelayUnavailableException(this.arch, this.remoteOs);
  final String arch;
  final RemoteOs remoteOs;
  @override
  String toString() =>
      'No relay available on the remote host (os=${remoteOs.name}, arch="$arch": '
      'no socat/nc and no bundled static relay for this os/arch). Cannot connect '
      'the remote member to the bus.';
}

/// Thrown when a bundled static relay IS the chosen strategy for [assetName] but
/// the binary is not packaged in this build. Surfaces at provision time with a
/// clear message rather than installing a broken file (see P3e §7.1).
class RelayAssetMissingException implements Exception {
  RelayAssetMissingException(this.assetName);
  final String assetName;
  @override
  String toString() =>
      'Bundled static relay "$assetName" is required for this remote host but is '
      'not packaged in this build. Install socat/nc on the remote, or ship the '
      'relay binary as an app asset.';
}

/// Layered relay provisioning (P3b POSIX + P3e Windows):
///
/// **POSIX remote** (`RemoteOs.posix`):
/// 1. prefer remote `socat` (zero distribution),
/// 2. else remote `nc`,
/// 3. else materialize a bundled static relay for the remote arch
///    (linux-x64 / linux-arm64),
/// 4. else throw [RelayUnavailableException].
///
/// **Windows remote** (`RemoteOs.windows`): Windows OpenSSH almost never ships
/// socat/nc and the `sh -c` handshake wrapper does not exist, so the bundled
/// static relay (which self-sends the handshake via argv) is the only path:
/// 1. materialize the bundled static relay for the windows arch (windows-x64),
/// 2. else throw [RelayUnavailableException].
///
/// The bundled binary bytes come from an injectable [RelayAssetResolver]; when
/// unavailable, [RelayAssetMissingException] is thrown (no silent broken file).
class RelayProvisioner {
  const RelayProvisioner({this.assetResolver});

  /// Resolves bundled relay binary bytes. Null field → always "missing" (the
  /// default until a binary is packaged), so a Windows / no-socat host fails
  /// with a clear error rather than a broken path.
  final RelayAssetResolver? assetResolver;

  /// Directory on the remote host where a bundled relay is materialized.
  static const bundledRelayDir = '.flashskyai/relay';

  static const _supportedPosixArch = {'linux-x64', 'linux-arm64'};
  static const _supportedWindowsArch = {'windows-x64', 'windows-arm64'};

  Future<RelayPlan> provision({
    required Filesystem remoteFs,
    required RemoteCommandRunner run,
    required int tunnelPort,
    required String token,
    required String memberId,
    required String arch,
    RemoteOs remoteOs = RemoteOs.posix,
  }) async {
    if (remoteOs == RemoteOs.windows) {
      return _provisionWindows(
        remoteFs: remoteFs,
        run: run,
        tunnelPort: tunnelPort,
        token: token,
        memberId: memberId,
        arch: arch,
      );
    }
    return _provisionPosix(
      remoteFs: remoteFs,
      run: run,
      tunnelPort: tunnelPort,
      token: token,
      memberId: memberId,
      arch: arch,
    );
  }

  Future<RelayPlan> _provisionPosix({
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

    final bundled = await _materializeBundledRelay(
      remoteFs,
      run,
      arch,
      RemoteOs.posix,
    );
    if (bundled == null) throw RelayUnavailableException(arch, RemoteOs.posix);
    return RelayPlan(
      kind: RelayKind.bundledStatic,
      argv: _bundledArgv(bundled, tunnelPort, token, memberId),
    );
  }

  Future<RelayPlan> _provisionWindows({
    required Filesystem remoteFs,
    required RemoteCommandRunner run,
    required int tunnelPort,
    required String token,
    required String memberId,
    required String arch,
  }) async {
    final bundled = await _materializeBundledRelay(
      remoteFs,
      run,
      arch,
      RemoteOs.windows,
    );
    if (bundled == null) throw RelayUnavailableException(arch, RemoteOs.windows);
    return RelayPlan(
      kind: RelayKind.bundledStatic,
      argv: _bundledArgv(bundled, tunnelPort, token, memberId),
    );
  }

  /// The bundled static relay self-sends the handshake (no shell wrapper), so
  /// its argv is identical on POSIX and Windows.
  List<String> _bundledArgv(
    String relayPath,
    int tunnelPort,
    String token,
    String memberId,
  ) => [
    relayPath,
    '127.0.0.1',
    '$tunnelPort',
    '--token',
    token,
    '--member',
    memberId,
  ];

  /// Shell wrapper: emit the handshake line, then bidirectionally pipe the CLI's
  /// stdio MCP traffic through [pipeCommand]. Works with socat/nc which cannot
  /// inject an initial frame themselves. POSIX-only (`sh -c`).
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

  /// Materializes the bundled static relay for ([arch], [os]) under
  /// [bundledRelayDir], writing bytes from the injected [assetResolver]. Returns
  /// the remote path, null when ([arch], [os]) is unsupported, and throws
  /// [RelayAssetMissingException] when the arch is supported but no binary is
  /// packaged (so the failure is explicit, not a broken path).
  Future<String?> _materializeBundledRelay(
    Filesystem fs,
    RemoteCommandRunner run,
    String arch,
    RemoteOs os,
  ) async {
    final supported = os == RemoteOs.windows
        ? _supportedWindowsArch
        : _supportedPosixArch;
    if (!supported.contains(arch)) return null;

    final ext = os == RemoteOs.windows ? '.exe' : '';
    final assetName = 'flashskyai-bus-relay-$arch$ext';
    final bytes = await (assetResolver ?? _noAsset)(assetName);
    if (bytes == null) throw RelayAssetMissingException(assetName);

    final path = fs.pathContext.join(bundledRelayDir, assetName);
    await fs.ensureDir(bundledRelayDir);
    await fs.writeBytes(path, bytes);
    if (os == RemoteOs.posix) {
      // Filesystem has no chmod primitive; set the exec bit over the command
      // runner (no-op cost on the happy path, required for the relay to run).
      await run('chmod +x ${_shellQuote(path)}');
    }
    return path;
  }

  static String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  static Future<List<int>?> _noAsset(String _) async => null;
}

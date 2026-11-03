import 'dart:convert';

import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';

/// Qoder CLI ACP quirks.
///
/// The CLI speaks ACP natively (`qodercli --acp`). The flag is hidden from
/// `--help`, so an upstream removal surfaces as "no initialize response" and
/// the runtime marks the CLI unsupported.
final class QoderAcpTranslator extends AcpAgentTranslator {
  const QoderAcpTranslator();

  @override
  List<String> get flagCandidates => const ['--acp'];

  @override
  List<String> get blockingClientMethods => const [];

  @override
  List<String> get notificationClientMethods => const [];

  @override
  String translateStopError(Object error, {required bool suppressAbort}) {
    if (error is RpcError) {
      if (error.code == ErrorCode.authRequired.code) {
        return acpStopAuthRequired;
      }
      final data = error.data;
      return 'ACP error ${error.code}: ${error.message}'
          '${data == null ? '' : ' $data'}';
    }
    return error.toString();
  }

  /// Qoder reports a prompt-turn failure as `stopReason: refusal` plus
  /// `_meta["qoder.ai/errorMessage"]` (a JSON string with `code`/`message`).
  /// Quota and auth failures both use that channel; surface the message (or
  /// the sign-in sentinel) so the turn does not end silently as a plain
  /// `refusal` → `aborted` stop. Non-refusal stops keep their plain reason.
  @override
  String? translateStopMeta(StopReason reason, Map<String, Object?> meta) {
    if (reason != StopReason.refusal) return null;
    final raw = meta['qoder.ai/errorMessage']?.toString() ?? '';
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (raw.contains('-32000') ||
        lower.contains('authentication') ||
        lower.contains('unauthorized') ||
        lower.contains('not logged in')) {
      return acpStopAuthRequired;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['message'] is String) {
        return (decoded['message'] as String).trim();
      }
    } on FormatException {
      // Not a JSON envelope.
    }
    return raw;
  }
}

/// Qoder launch/env declaration.
///
/// `QODER_CONFIG_DIR` isolates settings **and** `.auth`. The provider
/// capability seeds `.auth` into `sessionToolDir`; without it `session/new`
/// fails with auth-required, which is why no `authenticate` call is made.
final class QoderAcpCapability implements AcpCapability {
  const QoderAcpCapability();

  static const configDirEnvKey = 'QODER_CONFIG_DIR';

  @override
  String agentExecutable(String cliExecutable) => cliExecutable;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable, '--acp'],
  ];

  @override
  AcpAgentTranslator get translator => const QoderAcpTranslator();

  @override
  Duration get startupTimeout => const Duration(seconds: 30);

  @override
  String? get authenticateMethodId => null;

  @override
  Future<String?> resolveAuthenticateMethodId(Map<String, String> env) async =>
      authenticateMethodId;

  @override
  bool get forwardSessionNewMcpServers => false;

  @override
  Map<String, String> get agentStatusEnvironment => const {};

  @override
  Map<String, Object?> sessionNewMeta(Map<String, String> env) => const {};

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) {
    final env = Map<String, String>.of(baseEnv);
    env[configDirEnvKey] = sessionToolDir;
    return env;
  }
}

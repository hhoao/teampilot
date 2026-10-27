import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';

/// CodeBuddy ACP quirks.
///
/// The CLI speaks ACP natively on the same binary TeamPilot launches
/// (`codebuddy --acp`). `cbc` is an alias for the same executable.
///
/// The agent sends two private **notifications** (no JSON-RPC id) that
/// TeamPilot never has to answer: `_codebuddy.ai/command` (workspace info)
/// and `_codebuddy.ai/modResidentInvalidate`. They are declared as
/// notifications so a future client-side handler can subscribe without
/// changing the connection's blocking-method set.
final class CodebuddyAcpTranslator extends AcpAgentTranslator {
  const CodebuddyAcpTranslator();

  @override
  List<String> get flagCandidates => const ['--acp'];

  @override
  List<String> get blockingClientMethods => const [];

  @override
  List<String> get notificationClientMethods => const [
    '_codebuddy.ai/command',
    '_codebuddy.ai/modResidentInvalidate',
  ];

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

  /// CodeBuddy reports auth failures as `stopReason: refusal` plus
  /// `_meta["codebuddy.ai/errorMessage"]` (a JSON string with `code`/`message`)
  /// rather than a JSON-RPC error.
  @override
  String? translateStopMeta(StopReason reason, Map<String, Object?> meta) {
    if (reason != StopReason.refusal) return null;
    final raw = meta['codebuddy.ai/errorMessage']?.toString() ?? '';
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (raw.contains('-32000') ||
        lower.contains('auth') ||
        lower.contains('unauthorized') ||
        lower.contains('login')) {
      return acpStopAuthRequired;
    }
    return null;
  }
}

/// CodeBuddy's ACP launch/env declaration.
///
/// Auth is the machine's existing login (the CLI resolves it even with a
/// fresh `CODEBUDDY_CONFIG_DIR`), so no `authenticate` call is made —
/// `authenticateMethodId` is null, Cursor-style. `session/new` does not
/// forward MCP servers: TeamPilot stages `<configDir>/mcp.json` instead
/// (`forwardSessionNewMcpServers = false`), matching the CLI's own config
/// precedence.
final class CodebuddyAcpCapability implements AcpCapability {
  const CodebuddyAcpCapability();

  static const configDirEnvKey = 'CODEBUDDY_CONFIG_DIR';

  @override
  String agentExecutable(String cliExecutable) => cliExecutable;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable, '--acp'],
  ];

  @override
  AcpAgentTranslator get translator => const CodebuddyAcpTranslator();

  @override
  String? get authenticateMethodId => null;

  @override
  Future<String?> resolveAuthenticateMethodId(Map<String, String> env) async =>
      authenticateMethodId;

  @override
  bool get forwardSessionNewMcpServers => false;

  @override
  Map<String, Object?> sessionNewMeta(Map<String, String> env) => const {};

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) {
    final env = Map<String, String>.of(baseEnv);
    // The CLI's whole home (settings, mcp.json, skills, plugins, sessions)
    // lives here; `sessionRuntimeToolDir` is already `…/runtime/codebuddy`.
    env[configDirEnvKey] = sessionToolDir;
    return env;
  }
}

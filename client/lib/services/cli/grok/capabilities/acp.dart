import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';
import '../grok_constants.dart';

/// Grok Build ACP quirks.
///
/// Grok speaks ACP natively via `grok agent stdio`. User aborts surface as a
/// cancelled prompt; an unauthenticated agent reports ACP `auth_required`.
final class GrokAcpNoPtyFallback implements AcpNoPtyFallbackCapability {
  const GrokAcpNoPtyFallback();
}

final class GrokAcpUsageLog implements AcpUsageLogCapability {
  const GrokAcpUsageLog();
}

final class GrokAcpTranslator extends AcpAgentTranslator {
  const GrokAcpTranslator();

  @override
  List<String> get flagCandidates => const [];

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
}

/// Grok's ACP launch/env declaration.
///
/// `GROK_HOME` is pointed at the per-seat tool dir so `config.toml`, `skills/`,
/// `hooks/`, `plugins/`, `rules/`, and `auth.json` stay isolated from the
/// user's global `~/.grok`. The agent process reads MCP servers from that
/// config file (and still accepts `session/new.mcpServers`).
final class GrokAcpCapability implements AcpCapability {
  const GrokAcpCapability({AcpCredentialSource? credentialSource})
    : _credentialSource = credentialSource;

  final AcpCredentialSource? _credentialSource;

  @override
  String agentExecutable(String cliExecutable) => cliExecutable;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable, 'agent', 'stdio'],
  ];

  @override
  AcpAgentTranslator get translator => const GrokAcpTranslator();

  @override
  Duration get startupTimeout => const Duration(seconds: 30);

  @override
  String? get authenticateMethodId => null;

  @override
  // Grok reads the assembled set from `$GROK_HOME/config.toml` (written by
  // [GrokMcpCapability]); forwarding it again in session/new would duplicate
  // every server.
  bool get forwardSessionNewMcpServers => false;

  @override
  bool get supportsInPlaceSessionLoad => true;

  @override
  Map<String, String> get agentStatusEnvironment => const {};

  @override
  Map<String, Object?> sessionNewMeta(Map<String, String> env) => const {};

  @override
  Future<String?> resolveAuthenticateMethodId(Map<String, String> env) async =>
      authenticateMethodId;

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) {
    final env = Map<String, String>.of(baseEnv);
    // `GROK_HOME` isolates config; an inherited overlay would still merge
    // settings (including MCP) from the parent shell.
    env.remove('GROK_CONFIG');
    env.remove('GROK_CONFIG_PATH');
    // TeamPilot's provider row is the authority for xAI auth; an inherited
    // deployment key must not silently override an API key or OAuth login.
    env.remove('GROK_DEPLOYMENT_KEY');
    env[GrokConstants.homeEnvKey] = sessionToolDir;
    env['GROK_DISABLE_AUTOUPDATER'] = '1';
    // Provider-bound API keys are injected by materializeSessionHome; only
    // fall back to the app-wide cached key when the seat has none.
    if ((env[GrokConstants.apiKeyEnvKey] ?? '').trim().isEmpty) {
      final key = _credentialSource?.call()?.trim() ?? '';
      if (key.isNotEmpty) env[GrokConstants.apiKeyEnvKey] = key;
    }
    return env;
  }
}

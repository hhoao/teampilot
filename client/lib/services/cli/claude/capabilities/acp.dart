import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';

/// Claude absorption of ACP protocol quirks. The adapter
/// (`claude-agent-acp`) takes no ACP flag, and no abort workaround is needed.
final class ClaudeAcpTranslator implements AcpAgentTranslator {
  const ClaudeAcpTranslator();

  @override
  List<String> get flagCandidates => const [];

  @override
  String translateStopError(Object error, {required bool suppressAbort}) {
    if (error is RpcError) {
      return 'ACP error ${error.code}: ${error.message}';
    }
    return error.toString();
  }
}

/// Resolved Claude credentials for one ACP launch.
class ClaudeAcpAuth {
  const ClaudeAcpAuth({
    this.apiKey,
    this.authToken,
    this.official = false,
    this.officialCredentialsPath,
  });

  final String? apiKey;
  final String? authToken;

  /// Official (OAuth) login: no API key / auth token is ever injected.
  final bool official;

  /// Absolute path to Official `.credentials.json` to copy into CLAUDE_CONFIG_DIR.
  final String? officialCredentialsPath;
}

typedef ClaudeAcpAuthSource = ClaudeAcpAuth Function();

/// Claude's ACP launch/env declaration. Claude speaks ACP through the
/// `claude-agent-acp` adapter binary, not through the `claude` CLI itself.
final class ClaudeAcpCapability implements AcpCapability {
  const ClaudeAcpCapability({
    ClaudeAcpAuthSource? authSource,
    String Function(String cliExecutable)? locateAdapter,
    void Function(String destCredentialsPath, String srcPath)? copyFile,
  }) : _authSource = authSource,
       _locateAdapter = locateAdapter,
       _copyFile = copyFile;

  static const adapterName = 'claude-agent-acp';

  final ClaudeAcpAuthSource? _authSource;
  final String Function(String cliExecutable)? _locateAdapter;
  final void Function(String destCredentialsPath, String srcPath)? _copyFile;

  @override
  String agentExecutable(String cliExecutable) =>
      _locateAdapter?.call(cliExecutable) ?? adapterName;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable],
  ];

  @override
  AcpAgentTranslator get translator => const ClaudeAcpTranslator();

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) {
    final env = Map<String, String>.of(baseEnv);
    final configDir = '$sessionToolDir/claude';
    env['CLAUDE_CONFIG_DIR'] = configDir;
    final auth = _authSource?.call();
    if (auth == null) return env;
    if (auth.official) {
      env['CCGUI_CLI_LOGIN_AUTHORIZED'] = '1';
      final src = auth.officialCredentialsPath;
      if (src != null) _copyFile?.call('$configDir/.credentials.json', src);
    } else if (auth.apiKey != null) {
      env['ANTHROPIC_API_KEY'] = auth.apiKey!;
    } else if (auth.authToken != null) {
      env['ANTHROPIC_AUTH_TOKEN'] = auth.authToken!;
    }
    return env;
  }
}

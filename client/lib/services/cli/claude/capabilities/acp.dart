import 'dart:io';

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
    this.baseUrl,
    this.official = false,
    this.officialCredentialsPath,
  });

  final String? apiKey;
  final String? authToken;

  /// `ANTHROPIC_BASE_URL` for third-party providers; never set for Official.
  final String? baseUrl;

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
    // Process.start inherits the parent environment; overwrite with empty
    // strings so TeamPilot's own ANTHROPIC_* never reach the adapter.
    for (final key in _anthropicKeys) {
      env[key] = '';
    }
    final auth = _authSource?.call();
    if (auth == null) return env;
    if (auth.official) {
      env['CCGUI_CLI_LOGIN_AUTHORIZED'] = '1';
      final src = auth.officialCredentialsPath;
      if (src != null) {
        (_copyFile ?? _defaultCopyFile)('$configDir/.credentials.json', src);
      }
      return env;
    }
    final apiKey = auth.apiKey;
    final authToken = auth.authToken;
    final baseUrl = auth.baseUrl;
    if (apiKey != null) {
      env['ANTHROPIC_API_KEY'] = apiKey;
    } else if (authToken != null) {
      env['ANTHROPIC_AUTH_TOKEN'] = authToken;
    }
    if (baseUrl != null) env['ANTHROPIC_BASE_URL'] = baseUrl;
    return env;
  }

  static const _anthropicKeys = [
    'ANTHROPIC_API_KEY',
    'ANTHROPIC_AUTH_TOKEN',
    'ANTHROPIC_BASE_URL',
  ];

  static void _defaultCopyFile(String dest, String src) {
    final source = File(src);
    if (!source.existsSync()) return;
    File(dest).parent.createSync(recursive: true);
    source.copySync(dest);
  }
}

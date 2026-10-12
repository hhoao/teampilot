import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';

final class CodexAcpTranslator implements AcpAgentTranslator {
  const CodexAcpTranslator();

  @override
  List<String> get flagCandidates => const [];

  @override
  List<String> get blockingClientMethods => const [];

  @override
  List<String> get notificationClientMethods => const [];

  @override
  String translateStopError(Object error, {required bool suppressAbort}) {
    if (error is RpcError) {
      return 'ACP error ${error.code}: ${error.message}';
    }
    return error.toString();
  }
}

class CodexAcpAuth {
  const CodexAcpAuth({this.apiKey, this.official = false});

  final String? apiKey;
  final bool official;
}

typedef CodexAcpAuthSource = CodexAcpAuth Function();

final class CodexAcpCapability implements AcpCapability {
  const CodexAcpCapability({
    CodexAcpAuthSource? authSource,
    String Function(String cliExecutable)? locateAdapter,
    String Function()? codexPathSource,
  }) : _authSource = authSource,
       _locateAdapter = locateAdapter,
       _codexPathSource = codexPathSource;

  static const adapterName = 'codex-acp';
  static const _proxyManagedToken = 'PROXY_MANAGED';

  final CodexAcpAuthSource? _authSource;
  final String Function(String cliExecutable)? _locateAdapter;
  final String Function()? _codexPathSource;

  @override
  String agentExecutable(String cliExecutable) =>
      _locateAdapter?.call(cliExecutable) ?? adapterName;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable],
  ];

  @override
  AcpAgentTranslator get translator => const CodexAcpTranslator();

  @override
  String? get authenticateMethodId => null;

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) {
    final env = Map<String, String>.of(baseEnv);
    env['CODEX_HOME'] = sessionToolDir;
    env['CODEX_PATH'] = _codexPathSource?.call() ?? 'codex';
    for (final key in _keyNames) {
      env[key] = '';
    }
    final auth = _authSource?.call();
    if (auth == null || auth.official) return env;
    final apiKey = auth.apiKey?.trim() ?? '';
    if (apiKey.isEmpty || apiKey == _proxyManagedToken) return env;
    env['OPENAI_API_KEY'] = apiKey;
    env['CODEX_API_KEY'] = apiKey;
    return env;
  }

  static const _keyNames = ['OPENAI_API_KEY', 'CODEX_API_KEY'];
}

import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';

final class OpencodeAcpTranslator extends AcpAgentTranslator {
  const OpencodeAcpTranslator();

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
      return 'ACP error ${error.code}: ${error.message}';
    }
    return error.toString();
  }
}

final class OpencodeAcpCapability implements AcpCapability {
  const OpencodeAcpCapability();

  @override
  String agentExecutable(String cliExecutable) => cliExecutable;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable, 'acp'],
  ];

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
  AcpAgentTranslator get translator => const OpencodeAcpTranslator();

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) {
    return Map<String, String>.of(baseEnv);
  }
}

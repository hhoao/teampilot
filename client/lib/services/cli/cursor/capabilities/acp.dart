import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';

final class CursorAcpTranslator implements AcpAgentTranslator {
  const CursorAcpTranslator();

  @override
  List<String> get flagCandidates => const [];

  @override
  List<String> get blockingClientMethods => const [
    'cursor/ask_question',
    'cursor/create_plan',
  ];

  @override
  List<String> get notificationClientMethods => const [
    'cursor/update_todos',
    'cursor/task',
    'cursor/generate_image',
  ];

  @override
  String translateStopError(Object error, {required bool suppressAbort}) {
    if (error is RpcError) {
      return 'ACP error ${error.code}: ${error.message}';
    }
    return error.toString();
  }
}

final class CursorAcpCapability implements AcpCapability {
  const CursorAcpCapability();

  @override
  String agentExecutable(String cliExecutable) => cliExecutable;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable, 'acp'],
  ];

  @override
  String? get authenticateMethodId => 'cursor_login';

  @override
  AcpAgentTranslator get translator => const CursorAcpTranslator();

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) {
    return Map<String, String>.of(baseEnv);
  }
}

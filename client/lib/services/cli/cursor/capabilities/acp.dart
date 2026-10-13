import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../../io/filesystem.dart';
import '../../../io/local_filesystem.dart';
import '../../registry/capabilities/acp_capability.dart';
import '../provider/cursor_auth_artifacts.dart';
import '../provider/cursor_home_layout.dart';

final class CursorAcpTranslator extends AcpAgentTranslator {
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

  @override
  Map<String, Object?> encodePermissionResponse(
    RequestPermissionOutcome outcome,
  ) {
    return {'outcome': RequestPermissionResponse(outcome: outcome).toJson()};
  }
}

final class CursorAcpCapability implements AcpCapability {
  const CursorAcpCapability({this.fs, this.platform});

  final Filesystem? fs;
  final CursorHomePlatform? platform;

  @override
  String agentExecutable(String cliExecutable) => cliExecutable;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable, 'acp'],
  ];

  @override
  String? get authenticateMethodId => 'cursor_login';

  @override
  bool get forwardSessionNewMcpServers => false;

  @override
  Future<String?> resolveAuthenticateMethodId(Map<String, String> env) async {
    final home = (env['HOME'] ?? env['USERPROFILE'] ?? '').trim();
    if (home.isEmpty) return authenticateMethodId;
    final filesystem = fs ?? LocalFilesystem();
    final layout = CursorHomeLayout(
      pathContext: filesystem.pathContext,
      platform: platform,
    );
    final content = await filesystem.readString(layout.authJson(home));
    if (content != null &&
        CursorAuthArtifacts.authJsonIndicatesLoggedIn(content)) {
      return null;
    }
    return authenticateMethodId;
  }

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

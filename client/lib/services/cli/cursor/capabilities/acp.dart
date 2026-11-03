import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../../acp/acp_background_liveness.dart';
import '../../../io/filesystem.dart';
import '../../../io/local_filesystem.dart';
import '../../registry/capabilities/acp_background_liveness_capability.dart';
import '../../registry/capabilities/acp_capability.dart';
import '../provider/cursor_auth_artifacts.dart';
import '../provider/cursor_home_layout.dart';
import 'acp_background_liveness.dart';

final class CursorAcpTranslator extends AcpAgentTranslator {
  const CursorAcpTranslator();

  @override
  List<String> get flagCandidates => const [];

  @override
  List<String> get blockingClientMethods => const [
    'cursor/ask_question',
    'cursor/create_plan',
  ];

  /// Documented as notifications, but cursor-agent often sends them as
  /// JSON-RPC requests. The ACP session registrar acks both shapes.
  @override
  List<String> get notificationClientMethods => const [
    'cursor/update_todos',
    'cursor/task',
    'cursor/generate_image',
  ];

  /// Cursor's ACP agent waits for background children and resumes the parent
  /// turn (`backgroundTaskCompletionAction`) only after this capability.
  @override
  bool get advertisesBackgroundSubagents => true;

  @override
  String translateStopError(Object error, {required bool suppressAbort}) {
    if (error is RpcError) {
      return 'ACP error ${error.code}: ${error.message}';
    }
    return error.toString();
  }
}

final class CursorAcpCapability
    implements AcpCapability, AcpBackgroundLivenessCapability {
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
  Duration get startupTimeout => const Duration(seconds: 30);

  @override
  String? get authenticateMethodId => 'cursor_login';

  @override
  bool get forwardSessionNewMcpServers => false;

  @override
  Map<String, String> get agentStatusEnvironment => const {};

  @override
  Map<String, Object?> sessionNewMeta(Map<String, String> env) => const {};

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

  /// Cursor reports a background launch as a *completed* tool call
  /// (`rawOutput.isBackground`) and never reports when it ends, so the watch
  /// polls the child-agent transcripts / terminal metadata it leaves behind.
  @override
  AcpBackgroundLivenessProbe? createBackgroundLivenessProbe({
    required Filesystem fs,
    required String sessionToolDir,
    required String sessionId,
  }) => CursorBackgroundLivenessProbe(
    fs: fs,
    sessionToolDir: sessionToolDir,
    sessionId: sessionId,
  );
}

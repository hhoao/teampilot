import 'package:path/path.dart' as p;

import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../../../storage/runtime_layout.dart';
import '../../registry/capabilities/noop_cli_session_capability.dart';

final class AntigravityCliSessionCapability extends NoopCliSessionCapability {
  const AntigravityCliSessionCapability();

  String _home(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
  }) => p.join(
    layout.sessionRuntimeToolDir(
      workspaceId,
      sessionId,
      tool.value,
      memberId: memberId,
    ),
    'home',
  );

  @override
  String? sessionIsolatedHomeRoot(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }) => _home(
    layout,
    tool,
    workspaceId: workspaceId,
    sessionId: sessionId,
    memberId: memberId,
  );

  @override
  String sessionConfigDir(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }) => p.join(
    _home(
      layout,
      tool,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
    ),
    '.gemini',
    'config',
  );

  @override
  Future<String> prepareSessionIsolatedHome({
    required Filesystem fs,
    required String canonicalHome,
  }) async {
    await fs.ensureDir(canonicalHome);
    return canonicalHome;
  }
}

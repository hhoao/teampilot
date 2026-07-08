import 'package:path/path.dart' as p;

import '../../storage/runtime_layout.dart';
import 'cursor_home_layout.dart';

/// Resolves the on-disk config root cursor-agent reads for a session.
///
/// Both standalone and mixed mode isolate cursor under a fake `$HOME`, so the
/// config root is always `<toolDir>/home/.cursor/` — cursor reads `~/.cursor/*`
/// from there. (`CURSOR_CONFIG_DIR` only relocates `cli-config.json`/`chats`,
/// NOT the `.cursor` data dir where plugins/MCP/skills live, so HOME isolation
/// is required for those to take effect.)
abstract final class CursorSessionConfigDir {
  CursorSessionConfigDir._();

  static const toolId = 'cursor';
  static const homeSegment = 'home';

  static String resolve(
    RuntimeLayout layout, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }) {
    final trimmedMemberId = memberId?.trim() ?? '';
    final trimmedTeamId = teamId?.trim() ?? '';
    final toolDir = trimmedMemberId.isNotEmpty && trimmedTeamId.isNotEmpty
        ? layout.workspaceRuntimeMemberToolDir(
            workspaceId,
            trimmedTeamId,
            trimmedMemberId,
            toolId,
          )
        : layout.sessionRuntimeToolDir(
            workspaceId,
            sessionId,
            toolId,
          );
    return p.join(toolDir, homeSegment, CursorHomeLayout.cursorDirName);
  }

  /// Isolated fake `$HOME` for mixed-mode cursor (parent of `.cursor/`).
  static String mixedHomeRoot(
    RuntimeLayout layout, {
    required String workspaceId,
    required String teamId,
    required String memberId,
  }) {
    return p.join(
      layout.workspaceRuntimeMemberToolDir(
        workspaceId,
        teamId.trim(),
        memberId.trim(),
        toolId,
      ),
      homeSegment,
    );
  }
}

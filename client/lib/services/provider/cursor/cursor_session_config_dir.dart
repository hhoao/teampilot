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
  }) {
    final toolDir = layout.sessionRuntimeToolDir(
      workspaceId,
      sessionId,
      toolId,
      memberId: memberId,
    );
    return p.join(toolDir, homeSegment, CursorHomeLayout.cursorDirName);
  }

  /// Isolated fake `$HOME` for mixed-mode cursor (parent of `.cursor/`).
  static String mixedHomeRoot(
    RuntimeLayout layout, {
    required String workspaceId,
    required String sessionId,
    required String memberId,
  }) {
    return p.join(
      layout.sessionRuntimeToolDir(
        workspaceId,
        sessionId,
        toolId,
        memberId: memberId,
      ),
      homeSegment,
    );
  }
}

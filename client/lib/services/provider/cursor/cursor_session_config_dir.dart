import 'package:path/path.dart' as p;

import '../../storage/runtime_layout.dart';
import 'cursor_home_layout.dart';

/// Resolves the on-disk config root cursor-agent reads for a session.
///
/// - **Mixed mode** (`HOME=<toolDir>/home`): cursor-agent loads
///   `~/.cursor/*` → `<toolDir>/home/.cursor/`.
/// - **Standalone** (`CURSOR_CONFIG_DIR=<toolDir>`): the tool dir *is* the
///   config root (equivalent to `~/.cursor` on a real machine).
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
    final trimmedMember = memberId?.trim() ?? '';
    if (trimmedMember.isEmpty) return toolDir;
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

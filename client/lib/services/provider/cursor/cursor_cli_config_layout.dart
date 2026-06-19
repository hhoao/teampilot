import '../../../models/team_config.dart';
import '../../cli/registry/capabilities/cli_config_layout_capability.dart';
import '../../storage/runtime_layout.dart';
import 'cursor_session_config_dir.dart';

/// Cursor reads `~/.cursor/*`, so its session CONFIG_DIR is the isolated
/// `<toolDir>/home/.cursor` (mixed) or the tool dir itself (standalone) —
/// see [CursorSessionConfigDir].
final class CursorCliConfigLayout implements CliConfigLayoutCapability {
  const CursorCliConfigLayout();

  @override
  String sessionConfigDir(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
  }) =>
      CursorSessionConfigDir.resolve(
        layout,
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: memberId,
      );
}

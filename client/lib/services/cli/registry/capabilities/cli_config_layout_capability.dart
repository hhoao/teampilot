import '../../../../models/team_config.dart';
import '../../../storage/runtime_layout.dart';
import '../cli_capability.dart';
import '../cli_tool_registry.dart';

/// Resolves the on-disk CONFIG_DIR a CLI reads for a session/member.
///
/// Most CLIs use the standard `sessionRuntimeToolDir`. A CLI whose layout
/// differs (cursor isolates a fake `$HOME`) registers an override so the
/// knowledge lives in one capability instead of `if (cli == …)` branches
/// scattered across services.
abstract interface class CliConfigLayoutCapability implements CliCapability {
  String sessionConfigDir(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
  });
}

/// Standard layout: the session tool dir *is* the CONFIG_DIR.
final class DefaultCliConfigLayout implements CliConfigLayoutCapability {
  const DefaultCliConfigLayout();

  @override
  String sessionConfigDir(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
  }) =>
      layout.sessionRuntimeToolDir(
        workspaceId,
        sessionId,
        tool.value,
        memberId: memberId,
      );
}

/// Resolves the CONFIG_DIR for [tool] via its [CliConfigLayoutCapability],
/// falling back to [DefaultCliConfigLayout] when the CLI registers no override.
String sessionConfigDirForTool(
  CliTool tool,
  RuntimeLayout layout, {
  required String workspaceId,
  required String sessionId,
  String? memberId,
  CliToolRegistry? registry,
}) {
  final cap = (registry ?? CliToolRegistry.builtIn())
          .capability<CliConfigLayoutCapability>(tool) ??
      const DefaultCliConfigLayout();
  return cap.sessionConfigDir(
    layout,
    tool,
    workspaceId: workspaceId,
    sessionId: sessionId,
    memberId: memberId,
  );
}

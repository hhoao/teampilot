import '../../models/team_config.dart';
import '../storage/runtime_context.dart';

/// Workspace-level provision outcome cached per (target, workspace, cli).
class WorkspaceProvisionResult {
  const WorkspaceProvisionResult({
    required this.workContext,
    required this.remoteCliPath,
  });

  final RuntimeContext workContext;
  final String remoteCliPath;
}

class WorkspaceProvisionKey {
  const WorkspaceProvisionKey({
    required this.targetId,
    required this.workspaceId,
    required this.cli,
  });

  final String targetId;
  final String workspaceId;
  final CliTool cli;

  String get cacheKey => '$targetId|$workspaceId|${cli.value}';

  @override
  bool operator ==(Object other) =>
      other is WorkspaceProvisionKey &&
      targetId == other.targetId &&
      workspaceId == other.workspaceId &&
      cli == other.cli;

  @override
  int get hashCode => Object.hash(targetId, workspaceId, cli);
}

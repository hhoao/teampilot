import '../../registry/capabilities/prompt_provision_capability.dart';
import '../../../../services/session/member_role_provision.dart';
import '../../../launch/work_plane_paths.dart';

/// opencode 把成员 prompt（role + workspace dirs 章节）写入会话配置目录的
/// `AGENTS.md`；opencode 从 config dir 自动加载为全局指令，无 flag 传输。
final class OpencodePromptProvisionCapability
    implements PromptProvisionCapability {
  const OpencodePromptProvisionCapability();

  static const toolId = 'opencode';
  static const agentsFileName = 'AGENTS.md';

  @override
  Future<PromptProvisionContribution> provision(
    PromptProvisionContext ctx,
  ) async {
    final paths = ctx.paths;
    final scope = ctx.scope;
    if (paths == null || scope == null) {
      return const PromptProvisionContribution();
    }
    final member = ctx.member;
    final body = <String>[
      if (member != null && member.isValid)
        MemberRoleProvision.composeRolePrompt(
          member: member,
          forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
          mixed: ctx.mixed,
        ).trim(),
      MemberRoleProvision.composeWorkspaceDirectoriesPrompt(
        ctx.additionalDirectories,
      ).trim(),
    ].join('\n\n');
    if (body.isEmpty) return const PromptProvisionContribution();
    final opencodeDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    await paths.fs.atomicWrite(
      paths.joinWork(opencodeDir, agentsFileName),
      '$body\n',
    );
    return const PromptProvisionContribution(written: true);
  }
}

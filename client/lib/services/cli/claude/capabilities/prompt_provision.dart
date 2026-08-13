import '../../../../utils/team/team_member_naming.dart';
import '../../registry/capabilities/prompt_provision_capability.dart';
import '../../../../services/session/member_role_provision.dart';
import '../team_roster_service.dart';

/// claude 把成员 prompt 写入 `{toolDir}/prompts/{slug}/role.md`，通过
/// `TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE` env 传给 LaunchCommandBuilder
/// 转为 `--append-system-prompt-file`。
final class ClaudePromptProvisionCapability
    implements PromptProvisionCapability {
  const ClaudePromptProvisionCapability();

  static const toolId = 'claude';

  @override
  Future<PromptProvisionContribution> provision(
    PromptProvisionContext ctx,
  ) async {
    final paths = ctx.paths;
    final scope = ctx.scope;
    final member = ctx.member;
    if (paths == null ||
        scope == null ||
        member == null ||
        !member.isValid) {
      return const PromptProvisionContribution();
    }
    final isLead = TeamMemberNaming.isTeamLead(member);
    final memberToolDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: ctx.mixed
          ? ClaudeTeamRosterService.safeClaudePathSegment(member.id)
          : null,
    );
    final rolePath = await MemberRoleProvision.syncRolePromptFile(
      fs: paths.fs,
      memberToolDir: memberToolDir,
      member: member,
      forceTeamLeadDelegateMode: isLead && ctx.forceTeamLeadDelegateMode,
      mixed: ctx.mixed,
      additionalDirectories: const [],
    );
    if (rolePath == null) return const PromptProvisionContribution();
    return PromptProvisionContribution(
      written: true,
      environment: {
        MemberRoleProvision.appendSystemPromptFileEnvKey: rolePath,
      },
    );
  }
}

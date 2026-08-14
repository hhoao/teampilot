import '../../../../utils/team/team_member_naming.dart';
import '../../registry/capabilities/prompt_capability.dart';
import '../../../../services/session/member_role_provision.dart';
import '../team_roster_service.dart';

/// claude 把成员 prompt 写入 `{toolDir}/prompts/{slug}/role.md`，通过
/// `TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE` env 传给 LaunchCommandBuilder
/// 转为 `--append-system-prompt-file`。
final class ClaudePromptCapability implements PromptCapability {
  const ClaudePromptCapability();

  static const toolId = 'claude';

  @override
  List<PromptSpec> virtualize(PromptVirtualizeContext ctx) {
    final member = ctx.member;
    if (member == null || !member.isValid) return const [];
    return [
      PromptSpec(
        id: 'claude-member-role',
        title: 'Member role',
        scope: PromptScope.member,
        content: MemberRoleProvision.composeRolePrompt(member: member),
      ),
    ];
  }

  @override
  Future<PromptMaterializeResult> materialize(
    PromptMaterializeContext ctx,
  ) async {
    final paths = ctx.paths;
    final scope = ctx.scope;
    final member = ctx.member;
    if (paths == null ||
        scope == null ||
        member == null ||
        !member.isValid) {
      return const PromptMaterializeResult();
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
    if (rolePath == null) return const PromptMaterializeResult();
    return PromptMaterializeResult(
      written: true,
      environment: {
        MemberRoleProvision.appendSystemPromptFileEnvKey: rolePath,
      },
    );
  }
}

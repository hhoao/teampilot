import '../../../../utils/team/team_member_naming.dart';
import '../../registry/capabilities/prompt_capability.dart';
import '../../../../services/session/member_role_provision.dart';

final class FlashskyaiPromptCapability implements PromptCapability {
  const FlashskyaiPromptCapability();

  static const toolId = 'flashskyai';

  @override
  List<PromptSpec> virtualize(PromptVirtualizeContext ctx) {
    final member = ctx.member;
    if (member == null || !member.isValid) return const [];
    return [
      PromptSpec(
        id: 'flashskyai-member-role',
        title: 'Member role',
        scope: PromptScope.member,
        content: MemberRoleProvision.composeRolePrompt(
          member: member,
          forceTeamLeadDelegateMode:
              TeamMemberNaming.isTeamLead(member) && ctx.forceTeamLeadDelegateMode,
          mixed: ctx.mixed,
          additionalDirectories: const [],
        ),
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
      memberId: scope.memberId,
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

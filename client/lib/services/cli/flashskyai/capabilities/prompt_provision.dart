import '../../../../utils/team/team_member_naming.dart';
import '../../registry/capabilities/prompt_provision_capability.dart';
import '../../../../services/session/member_role_provision.dart';

final class FlashskyaiPromptProvisionCapability
    implements PromptProvisionCapability {
  const FlashskyaiPromptProvisionCapability();

  static const toolId = 'flashskyai';

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
    if (rolePath == null) return const PromptProvisionContribution();
    return PromptProvisionContribution(
      written: true,
      environment: {
        MemberRoleProvision.appendSystemPromptFileEnvKey: rolePath,
      },
    );
  }
}

import '../../../../utils/team/team_member_naming.dart';
import 'dart:async';

import '../../registry/capabilities/prompt_capability.dart';
import '../../../../services/session/member_role_provision.dart';
import '../../../resource/providers/prompt_contribution_provider.dart';
import '../../../resource/contribution/resource_origin.dart';

final class FlashskyaiPromptCapability
    implements PromptCapability, PromptContributionProvider {
  const FlashskyaiPromptCapability();

  static const toolId = 'flashskyai';

  @override
  String get providerId => toolId;

  @override
  FutureOr<Iterable<PromptContribution>> provide(PromptProviderContext ctx) {
    final member = ctx.member;
    if (member == null || !member.isValid) return const [];
    return [
      PromptContribution(
        id: 'flashskyai-member-role',
        title: 'Member role',
        scope: PromptScope.member,
        content: MemberRoleProvision.composeRolePrompt(
          member: member,
          forceTeamLeadDelegateMode:
              TeamMemberNaming.isTeamLead(member) &&
              ctx.forceTeamLeadDelegateMode,
          mixed: ctx.mixed,
          additionalDirectories: const [],
        ),
        origin: const ContributionOrigin(
          providerId: toolId,
          kind: ResourceOriginKind.cliBuiltIn,
          sourceId: 'flashskyai-member-role',
        ),
      ),
    ];
  }

  @override
  Future<PromptMaterializeResult> materialize(
    PromptMaterializeContext ctx, {
    required PromptDocument document,
  }) async {
    final paths = ctx.paths;
    final scope = ctx.scope;
    final member = ctx.member;
    if (paths == null || scope == null || member == null || !member.isValid) {
      return const PromptMaterializeResult();
    }
    final memberToolDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    final rolePath = MemberRoleProvision.rolePromptPath(memberToolDir, member);
    final body = document.content;
    final stat = await paths.fs.stat(rolePath);
    if (body.isEmpty) {
      if (stat.exists) await paths.fs.removeRecursive(rolePath);
      return const PromptMaterializeResult();
    }
    await paths.fs.ensureDir(paths.fs.pathContext.dirname(rolePath));
    await paths.fs.atomicWrite(rolePath, '$body\n');
    return PromptMaterializeResult(
      written: true,
      environment: {MemberRoleProvision.appendSystemPromptFileEnvKey: rolePath},
    );
  }
}

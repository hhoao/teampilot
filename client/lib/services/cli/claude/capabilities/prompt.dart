import 'dart:async';

import '../../../../utils/team/team_member_naming.dart';
import '../../registry/capabilities/prompt_capability.dart';
import '../../../../services/session/member_role_provision.dart';
import '../team_roster_service.dart';
import '../../../resource/contribution/resource_origin.dart';

/// claude 把成员 prompt 写入 `{toolDir}/prompts/{slug}/role.md`，通过
/// `TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE` env 传给 LaunchCommandBuilder
/// 转为 `--append-system-prompt-file`。
final class ClaudePromptCapability
    implements PromptCapability, PromptContributionProvider {
  const ClaudePromptCapability();

  static const toolId = 'claude';

  @override
  String get providerId => toolId;

  @override
  FutureOr<Iterable<PromptContribution>> provide(PromptProviderContext ctx) {
    final member = ctx.member;
    if (member == null || !member.isValid) return const [];
    return [
      PromptContribution(
        id: 'claude-member-role',
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
          sourceId: 'claude-member-role',
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
      memberId: ctx.mixed
          ? ClaudeTeamRosterService.safeClaudePathSegment(member.id)
          : null,
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

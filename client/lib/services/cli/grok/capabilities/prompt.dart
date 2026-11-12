import 'dart:async';

import '../../../chat/launch/staging/manifest/work_plane_paths.dart';
import '../../registry/capabilities/prompt_capability.dart';
import '../../registry/member_role_provision.dart';
import '../../../resource/contribution/resource_origin.dart';

/// Grok reads user-scoped rules from `$GROK_HOME/rules/*.md`, and the ACP
/// launch points `GROK_HOME` at the session tool dir. The assembled member
/// prompt is materialized there.
final class GrokPromptCapability
    implements PromptCapability, PromptContributionProvider {
  const GrokPromptCapability();

  static const toolId = 'grok';

  @override
  String get providerId => toolId;

  @override
  FutureOr<Iterable<PromptContribution>> provide(PromptProviderContext ctx) {
    final member = ctx.member;
    if (member == null || !member.isValid) return const [];
    return [
      PromptContribution(
        id: 'grok-member-role',
        title: 'Member role',
        scope: PromptScope.member,
        content: MemberRoleProvision.composeRolePrompt(
          member: member,
          forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
          mixed: ctx.mixed,
        ).trim(),
        origin: const ContributionOrigin(
          providerId: toolId,
          kind: ResourceOriginKind.cliBuiltIn,
          sourceId: 'grok-member-role',
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
    final toolDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    final path = paths.joinWork(toolDir, 'rules', 'teampilot.md');
    final body = document.content;
    if (body.isEmpty) {
      final stat = await paths.fs.stat(path);
      if (stat.exists) await paths.fs.removeRecursive(path);
      return const PromptMaterializeResult();
    }
    await paths.fs.ensureDir(paths.fs.pathContext.dirname(path));
    await paths.fs.atomicWrite(path, '$body\n');
    return const PromptMaterializeResult(written: true);
  }
}

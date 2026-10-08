import 'dart:async';

import '../../registry/capabilities/prompt_capability.dart';
import '../../registry/member_role_provision.dart';
import '../../../chat/launch/staging/manifest/work_plane_paths.dart';
import '../../../resource/contribution/resource_origin.dart';

/// Gemini reads a `GEMINI.md` hierarchical memory file from its config dir;
/// the member role prompt is materialized there for this phase.
final class GeminiPromptCapability
    implements PromptCapability, PromptContributionProvider {
  const GeminiPromptCapability();

  static const toolId = 'gemini';
  static const contextFileName = 'GEMINI.md';

  @override
  String get providerId => toolId;

  @override
  FutureOr<Iterable<PromptContribution>> provide(PromptProviderContext ctx) {
    final member = ctx.member;
    if (member == null || !member.isValid) return const [];
    return [
      PromptContribution(
        id: 'gemini-member-role',
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
          sourceId: 'gemini-member-role',
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
    final prompt = document.content;
    if (prompt.isEmpty) return const PromptMaterializeResult();
    final configDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    await paths.fs.ensureDir(configDir);
    await paths.fs.atomicWrite(
      paths.joinWork(configDir, contextFileName),
      '$prompt\n',
    );
    return const PromptMaterializeResult(written: true);
  }
}

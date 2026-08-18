import 'dart:async';

import '../../registry/capabilities/prompt_capability.dart';
import '../../../../services/session/member_role_provision.dart';
import '../../../launch/work_plane_paths.dart';
import '../../../resource/providers/prompt_contribution_provider.dart';
import '../../../resource/contribution/resource_origin.dart';

/// codex 把成员 prompt 写入 `$CODEX_HOME/AGENTS.md`；codex 自动加载为全局指令。
final class CodexPromptCapability
    implements PromptCapability, PromptContributionProvider {
  const CodexPromptCapability();

  static const toolId = 'codex';
  static const agentsFileName = 'AGENTS.md';

  @override
  String get providerId => toolId;

  @override
  FutureOr<Iterable<PromptContribution>> provide(PromptProviderContext ctx) {
    final member = ctx.member;
    if (member == null || !member.isValid) return const [];
    return [
      PromptContribution(
        id: 'codex-member-role',
        title: 'Member role',
        scope: PromptScope.member,
        content: MemberRoleProvision.composeRolePrompt(
          member: member,
          forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
          mixed: ctx.mixed,
          additionalDirectories: const [],
        ).trim(),
        origin: const ContributionOrigin(
          providerId: toolId,
          kind: ResourceOriginKind.cliBuiltIn,
          sourceId: 'codex-member-role',
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
    final codexHome = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    await paths.fs.atomicWrite(
      paths.joinWork(codexHome, agentsFileName),
      '$prompt\n',
    );
    return const PromptMaterializeResult(written: true);
  }
}

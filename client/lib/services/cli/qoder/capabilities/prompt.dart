import 'dart:async';

import '../../../chat/launch/staging/manifest/work_plane_paths.dart';
import '../../../resource/contribution/resource_origin.dart';
import '../../registry/capabilities/prompt_capability.dart';
import '../../registry/member_role_provision.dart';
import '../qoder_flavor.dart';

/// Qoder reads a hierarchical `AGENTS.md` memory file (user-level one lives in
/// `QODER_CONFIG_DIR`); the member role prompt is materialized there.
final class QoderPromptCapability
    implements PromptCapability, PromptContributionProvider {
  const QoderPromptCapability({this.flavor = QoderFlavor.global});

  final QoderFlavor flavor;

  static const contextFileName = 'AGENTS.md';

  String get toolId => flavor.cli.value;

  @override
  String get providerId => toolId;

  @override
  FutureOr<Iterable<PromptContribution>> provide(PromptProviderContext ctx) {
    final member = ctx.member;
    if (member == null || !member.isValid) return const [];
    final roleId = '$toolId-member-role';
    return [
      PromptContribution(
        id: roleId,
        title: 'Member role',
        scope: PromptScope.member,
        content: MemberRoleProvision.composeRolePrompt(
          member: member,
          forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
          mixed: ctx.mixed,
        ).trim(),
        origin: ContributionOrigin(
          providerId: toolId,
          kind: ResourceOriginKind.cliBuiltIn,
          sourceId: roleId,
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

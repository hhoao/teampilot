import 'dart:async';

import 'package:path/path.dart' as p;

import '../../registry/capabilities/prompt_capability.dart';
import '../../registry/member_role_provision.dart';
import '../../../resource/contribution/resource_origin.dart';

/// Antigravity (Gemini-family) reads project rules from
/// `<config>/rules/*.md` under its fake HOME, so the assembled prompt is
/// materialized there instead of a `GEMINI.md` memory file.
abstract final class AntigravityPromptPaths {
  static String rulesPath(String sessionToolDir) => p.join(
    sessionToolDir,
    'home',
    '.gemini',
    'config',
    'rules',
    'teampilot.md',
  );
}

final class AntigravityPromptCapability
    implements PromptCapability, PromptContributionProvider {
  const AntigravityPromptCapability();

  static const toolId = 'antigravity';

  @override
  String get providerId => toolId;

  @override
  FutureOr<Iterable<PromptContribution>> provide(PromptProviderContext ctx) {
    final member = ctx.member;
    if (member == null || !member.isValid) return const [];
    return [
      PromptContribution(
        id: 'antigravity-member-role',
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
          sourceId: 'antigravity-member-role',
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
    if (paths == null || scope == null) {
      return const PromptMaterializeResult();
    }
    final toolDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    final path = AntigravityPromptPaths.rulesPath(toolDir);
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

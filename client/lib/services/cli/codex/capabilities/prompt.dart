import '../../registry/capabilities/prompt_capability.dart';
import '../../../../services/session/member_role_provision.dart';
import '../../../launch/work_plane_paths.dart';

/// codex 把成员 prompt 写入 `$CODEX_HOME/AGENTS.md`；codex 自动加载为全局指令。
final class CodexPromptCapability implements PromptCapability {
  const CodexPromptCapability();

  static const toolId = 'codex';
  static const agentsFileName = 'AGENTS.md';

  @override
  List<PromptSpec> virtualize(PromptVirtualizeContext ctx) {
    final member = ctx.member;
    if (member == null || !member.isValid) return const [];
    return [
      PromptSpec(
        id: 'codex-member-role',
        title: 'Member role',
        scope: PromptScope.member,
        content: MemberRoleProvision.composeRolePrompt(
          member: member,
          forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
          mixed: ctx.mixed,
          additionalDirectories: const [],
        ).trim(),
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
    final prompt = MemberRoleProvision.composeRolePrompt(
      member: member,
      forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
      mixed: ctx.mixed,
      additionalDirectories: const [],
    ).trim();
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

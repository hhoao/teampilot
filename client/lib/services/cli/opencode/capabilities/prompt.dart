import '../../registry/capabilities/prompt_capability.dart';
import '../../../../services/session/member_role_provision.dart';
import '../../../launch/work_plane_paths.dart';

/// opencode 把成员 prompt（role + workspace dirs 章节）写入会话配置目录的
/// `AGENTS.md`；opencode 从 config dir 自动加载为全局指令，无 flag 传输。
final class OpencodePromptCapability implements PromptCapability {
  const OpencodePromptCapability();

  static const toolId = 'opencode';
  static const agentsFileName = 'AGENTS.md';

  @override
  List<PromptSpec> virtualize(PromptVirtualizeContext ctx) {
    final member = ctx.member;
    if (member == null || !member.isValid) return const [];
    return [
      PromptSpec(
        id: 'opencode-member-role',
        title: 'Member role',
        scope: PromptScope.member,
        content: MemberRoleProvision.composeRolePrompt(member: member).trim(),
      ),
    ];
  }

  @override
  Future<PromptMaterializeResult> materialize(
    PromptMaterializeContext ctx,
  ) async {
    final paths = ctx.paths;
    final scope = ctx.scope;
    if (paths == null || scope == null) {
      return const PromptMaterializeResult();
    }
    final member = ctx.member;
    final roleBody = member != null && member.isValid
        ? MemberRoleProvision.composeRolePrompt(
            member: member,
            forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
            mixed: ctx.mixed,
          ).trim()
        : '';
    final dirsPrompt = MemberRoleProvision.composeWorkspaceDirectoriesPrompt(
      ctx.additionalDirectories,
    ).trim();
    final body = <String>[
      if (roleBody.isNotEmpty) roleBody,
      if (dirsPrompt.isNotEmpty) dirsPrompt,
    ].join('\n\n');
    if (body.isEmpty) return const PromptMaterializeResult();
    final opencodeDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    await paths.fs.atomicWrite(
      paths.joinWork(opencodeDir, agentsFileName),
      '$body\n',
    );
    return const PromptMaterializeResult(written: true);
  }
}

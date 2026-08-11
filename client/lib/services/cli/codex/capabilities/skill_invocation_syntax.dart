import '../../registry/capabilities/skill_invocation_syntax_capability.dart';

/// Codex: `$superpowers:using-git-worktrees`.
final class CodexSkillInvocationSyntaxCapability
    implements SkillInvocationSyntaxCapability {
  const CodexSkillInvocationSyntaxCapability();

  @override
  String get skillInvocationPrefix => r'$';

  @override
  String skillInvocationText(String skillName, {String? namespace}) {
    final ns = namespace != null && namespace.trim().isNotEmpty
        ? '$namespace:'
        : '';
    return r'$' '$ns$skillName';
  }
}

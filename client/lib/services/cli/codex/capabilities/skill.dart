import '../../registry/capabilities/skill_capability.dart';

/// Codex: `$superpowers:using-git-worktrees`.
final class CodexSkillCapability
    with SkillCapabilityMaterializationMixin
    implements SkillCapability {
  const CodexSkillCapability();

  @override
  String get skillsSubdir => 'skills';

  @override
  ResourceRepresentation get skillsRepresentation =>
      ResourceRepresentation.linkedDirectory;

  @override
  String get skillInvocationPrefix => r'$';

  @override
  String skillInvocationText(String skillName, {String? namespace}) {
    final ns = namespace != null && namespace.trim().isNotEmpty
        ? '$namespace:'
        : '';
    return r'$'
        '$ns$skillName';
  }
}

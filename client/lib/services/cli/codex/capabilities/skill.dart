import '../../registry/capabilities/skill_capability.dart';
import '../../../resource/skill_link_name.dart';

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
    final safeSkillName = targetSafeSkillLinkName(skillName);
    final trimmedNamespace = namespace?.trim();
    if (trimmedNamespace == null || trimmedNamespace.isEmpty) {
      return '\$$safeSkillName';
    }
    final safeNamespace = targetSafeSkillLinkName(trimmedNamespace);
    return '\$$safeNamespace:$safeSkillName';
  }
}

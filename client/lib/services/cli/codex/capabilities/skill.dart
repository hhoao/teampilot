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
    return r'$'
        '${targetSafeSkillLinkName(skillName, namespace: namespace)}';
  }
}

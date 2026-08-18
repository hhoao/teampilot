import '../../registry/capabilities/skill_capability.dart';

/// Cursor-agent loads skills from `<cursorConfigDir>/skills-cursor/`.
final class CursorSkillCapability
    with SkillCapabilityMaterializationMixin
    implements SkillCapability {
  const CursorSkillCapability();

  static const skillsSubdirName = 'skills-cursor';

  static const _syntax = DefaultSkillInvocationSyntaxCapability();

  @override
  String get skillsSubdir => skillsSubdirName;

  @override
  ResourceRepresentation get skillsRepresentation =>
      ResourceRepresentation.linkedDirectory;

  @override
  String get skillInvocationPrefix => _syntax.skillInvocationPrefix;

  @override
  String skillInvocationText(String skillName, {String? namespace}) =>
      _syntax.skillInvocationText(skillName, namespace: namespace);
}

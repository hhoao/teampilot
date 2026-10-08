import '../../registry/capabilities/skill_capability.dart';

/// OpenCode v2 discovers skills under `skills/` (plural). Slash commands are
/// only recognized when the `/` is preceded by whitespace, so a space is
/// inserted before the reference. Plugin skills stay `/name` — OpenCode does
/// not use Claude's `/plugin:name` namespace.
final class OpencodeSkillCapability
    with SkillCapabilityMaterializationMixin
    implements SkillCapability {
  const OpencodeSkillCapability();

  static const _syntax = DefaultSkillInvocationSyntaxCapability(
    leadingSeparator: ' ',
  );

  @override
  String get skillsSubdir => 'skills';

  @override
  ResourceRepresentation get skillsRepresentation =>
      ResourceRepresentation.linkedDirectory;

  @override
  String get skillInvocationPrefix => _syntax.skillInvocationPrefix;

  @override
  String skillInvocationText(String skillName, {String? namespace}) =>
      _syntax.skillInvocationText(skillName);
}

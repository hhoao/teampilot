import '../../registry/capabilities/skill_capability.dart';

/// opencode names its skills directory `skill` (singular), and its slash
/// commands are only recognized when the `/` is preceded by whitespace, so a
/// space is inserted before the reference.
final class OpencodeSkillCapability
    with SkillCapabilityMaterializationMixin
    implements SkillCapability {
  const OpencodeSkillCapability();

  static const _syntax = DefaultSkillInvocationSyntaxCapability(
    leadingSeparator: ' ',
  );

  @override
  String get skillsSubdir => 'skill';

  @override
  ResourceRepresentation get skillsRepresentation =>
      ResourceRepresentation.linkedDirectory;

  @override
  String get skillInvocationPrefix => _syntax.skillInvocationPrefix;

  @override
  String skillInvocationText(String skillName, {String? namespace}) =>
      _syntax.skillInvocationText(skillName, namespace: namespace);
}

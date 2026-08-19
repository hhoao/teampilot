import '../capabilities/skill_capability.dart';

/// Default: skills land in a `skills/` directory and are invoked as
/// `/skill-name`. Plugin/MCP support is added by their follow-on plans.
final class DefaultSkillCapability
    with SkillCapabilityMaterializationMixin
    implements SkillCapability {
  const DefaultSkillCapability();

  static const _syntax = DefaultSkillInvocationSyntaxCapability();

  @override
  String get skillsSubdir => 'skills';

  @override
  ResourceRepresentation get skillsRepresentation =>
      ResourceRepresentation.linkedDirectory;

  @override
  String get skillInvocationPrefix => _syntax.skillInvocationPrefix;

  @override
  String skillInvocationText(String skillName, {String? namespace}) =>
      _syntax.skillInvocationText(skillName, namespace: namespace);
}

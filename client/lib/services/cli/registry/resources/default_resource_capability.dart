import '../capabilities/skill_capability.dart';

/// Default: skills land in a `skills/` directory and are invoked as
/// `/skill-name` or `/plugin:skill`. Plugin skills are not duplicated into
/// `skills/` — Claude-family CLIs load them from the plugin bundle.
final class DefaultSkillCapability
    with SkillCapabilityMaterializationMixin
    implements SkillCapability {
  const DefaultSkillCapability();

  static const _syntax = DefaultSkillInvocationSyntaxCapability();

  @override
  String get skillsSubdir => 'skills';

  @override
  bool get linksPluginSkills => false;

  @override
  ResourceRepresentation get skillsRepresentation =>
      ResourceRepresentation.linkedDirectory;

  @override
  String get skillInvocationPrefix => _syntax.skillInvocationPrefix;

  @override
  String skillInvocationText(String skillName, {String? namespace}) =>
      _syntax.skillInvocationText(skillName, namespace: namespace);
}

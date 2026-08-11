import '../../registry/capabilities/skill_invocation_syntax_capability.dart';

/// opencode's slash commands are only recognized when the `/` is preceded by
/// whitespace, so a space is inserted before the reference.
final class OpencodeSkillInvocationSyntaxCapability
    extends DefaultSkillInvocationSyntaxCapability {
  const OpencodeSkillInvocationSyntaxCapability()
    : super(leadingSeparator: ' ');
}

import '../../registry/capabilities/member_agent_preset_capability.dart';

final class ClaudeMemberAgentPreset implements MemberAgentPresetCapability {
  const ClaudeMemberAgentPreset();

  @override
  MemberAgentPresetStyle get style => MemberAgentPresetStyle.claudeAgentType;
}

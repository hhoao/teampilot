import '../../registry/capabilities/member_agent_preset_capability.dart';

final class FlashskyaiMemberAgentPreset implements MemberAgentPresetCapability {
  const FlashskyaiMemberAgentPreset();

  @override
  MemberAgentPresetStyle get style => MemberAgentPresetStyle.flashskyaiCatalog;
}

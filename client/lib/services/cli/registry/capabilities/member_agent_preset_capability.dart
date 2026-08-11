import '../cli_capability.dart';

/// Member [TeamMemberConfig.agent] is wired into this CLI at launch (e.g.
/// flashskyai `--agent`, Claude roster `agentType`).
abstract interface class MemberAgentPresetCapability implements CliCapability {
  MemberAgentPresetStyle get style;
}

enum MemberAgentPresetStyle {
  /// Built-in + user `agents/*.md` catalog ([FlashskyaiAgentCatalog]).
  flashskyaiCatalog,

  /// Free-text roster `agentType` (falls back to member id when empty).
  claudeAgentType,
}


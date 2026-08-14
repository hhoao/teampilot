import '../cli_capability.dart';

/// 团队协作:原生团队、Bus 传输、turn 结束语义、wait-before-stop、presence、成员 agent 预设。
abstract interface class TeamBehaviorCapability implements CliCapability {
  /// The CLI implements first-party multi-agent native teams (roster + team flags),
  /// not merely parallel single-agent terminals under [TeamMode.native].
  ///
  /// Register on tool definitions that pass `--team-name` / `--team` (etc.) and
  /// provision a shared native roster. Mixed-mode teams use [TeamBus] instead and
  /// do not require this capability.
  bool get supportsNativeTeam;

  /// True when the CLI parks in a long-blocking `wait_for_message` (claude,
  /// flashskyai, codex, opencode); false for doorbell CLIs (cursor).
  bool get longBlockingWaitForMessage;

  /// Whether this CLI supports a local stdio bridge for bus transport.
  /// Only claude currently uses this.
  bool get supportsLocalStdioBridge;

  /// Agent-status hook event names that mean "turn ended" (→ done).
  Set<String> get doneEventNames;

  /// Whether the PTY-quiet turn-end fallback may clear the seat
  /// (done event may be unreliable for this CLI).
  bool get requiresPtyFallback;

  /// Whether this is a doorbell-push CLI (mixed mode: `/idle` must end the
  /// bus turn).
  bool get usesDoorbellPush;

  /// CLI default when [TeamMemberConfig.forceWaitBeforeStop] is null.
  ///
  /// Cursor returns `false` — its MCP tools have an agent hard limit of ~60s
  /// and cannot block in `wait_for_message`.
  bool get defaultForceWaitBeforeStop;

  bool get usesClaudeRoster;

  bool get usesShellActivity;

  /// Member [TeamMemberConfig.agent] is wired into this CLI at launch (e.g.
  /// flashskyai `--agent`, Claude roster `agentType`). Unsupported CLIs
  /// return null.
  MemberAgentPresetStyle? get agentPresetStyle;
}

enum MemberAgentPresetStyle {
  /// Built-in + user `agents/*.md` catalog ([FlashskyaiAgentCatalog]).
  flashskyaiCatalog,

  /// Free-text roster `agentType` (falls back to member id when empty).
  claudeAgentType,
}

import '../cli_capability.dart';

/// Identifies the agent-status normalization strategy for this CLI.
///
/// Three profiles:
/// - `claude_family` — claude, flashskyai, codex (identical SSE event shape)
/// - `opencode` — opencode-specific event format
/// - `cursor` — cursor hook events (camelCase, title-based waiting)
///
/// Replaces the `switch(cli)` in [AgentStatusNormalizer].
abstract interface class AgentStatusNormalizerCapability implements CliCapability {
  String get profile;
}

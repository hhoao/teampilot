import '../../../agent_status/agent_status_event.dart';
import '../cli_capability.dart';

/// Normalizes a raw CLI hook / plugin payload into a shared [AgentStatusEvent].
///
/// Each CLI implements its own payload grammar in its own directory
/// (claude/codex/flashskyai share the [ClaudeFamilyAgentStatusNormalizer]);
/// the shared [AgentStatusNormalizer] facade only looks this capability up.
abstract interface class AgentStatusNormalizerCapability
    implements CliCapability {
  /// Returns `null` for corrupt or unknown payloads.
  AgentStatusEvent? normalize(Map<String, Object?> body);
}

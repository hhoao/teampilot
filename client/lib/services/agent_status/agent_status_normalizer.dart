import '../cli/registry/capabilities/chat_interaction_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../../models/team_config.dart';
import 'agent_status_event.dart';

/// Dispatches raw CLI hook / plugin JSON to the CLI's own
/// [ChatInteractionCapability] normalize.
///
/// Pure: no I/O. The per-CLI payload grammars (claude family, opencode,
/// cursor) live in each CLI's directory; this facade only looks up the
/// capability so callers never switch on [CliTool].
class AgentStatusNormalizer {
  const AgentStatusNormalizer._();

  static AgentStatusEvent? normalize({
    required CliTool cli,
    required Map<String, Object?> body,
  }) {
    return CliToolRegistry.builtIn()
        .capability<ChatInteractionCapability>(cli)
        ?.normalize(body);
  }
}

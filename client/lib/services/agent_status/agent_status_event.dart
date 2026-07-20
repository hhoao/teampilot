import 'agent_attention_state.dart';

/// Normalized agent-status signal from a CLI hook / plugin payload.
class AgentStatusEvent {
  const AgentStatusEvent({required this.state, this.toolName});

  final AgentSeatAttention state;
  final String? toolName;
}

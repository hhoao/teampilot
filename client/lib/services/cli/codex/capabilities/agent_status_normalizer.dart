import '../../registry/capabilities/agent_status_normalizer_capability.dart';

final class ClaudeFamilyAgentStatusNormalizer implements AgentStatusNormalizerCapability {
  const ClaudeFamilyAgentStatusNormalizer();
  @override String get profile => 'claude_family';
}

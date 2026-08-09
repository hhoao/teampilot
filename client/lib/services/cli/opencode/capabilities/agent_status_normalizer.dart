import '../../registry/capabilities/agent_status_normalizer_capability.dart';

final class OpencodeAgentStatusNormalizer implements AgentStatusNormalizerCapability {
  const OpencodeAgentStatusNormalizer();
  @override String get profile => 'opencode';
}

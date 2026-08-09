import '../../registry/capabilities/agent_status_normalizer_capability.dart';

final class CursorAgentStatusNormalizer implements AgentStatusNormalizerCapability {
  const CursorAgentStatusNormalizer();
  @override String get profile => 'cursor';
}

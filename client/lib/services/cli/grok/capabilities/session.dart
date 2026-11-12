import '../../registry/capabilities/noop_cli_session_capability.dart';

/// Grok session lifecycle: noop (the ACP session owns the transcript).
final class GrokCliSessionCapability extends NoopCliSessionCapability {
  const GrokCliSessionCapability();
}

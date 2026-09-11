import '../../registry/capabilities/noop_cli_session_capability.dart';

/// Gemini session capability: noop lifecycle + standard CONFIG_DIR layout.
final class GeminiCliSessionCapability extends NoopCliSessionCapability {
  const GeminiCliSessionCapability();
}

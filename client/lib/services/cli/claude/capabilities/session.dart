import '../../registry/capabilities/noop_cli_session_capability.dart';

/// Claude session capability: noop lifecycle + standard CONFIG_DIR layout.
final class ClaudeCliSessionCapability extends NoopCliSessionCapability {
  const ClaudeCliSessionCapability();
}

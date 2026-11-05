import '../../registry/capabilities/noop_cli_session_capability.dart';

/// Qoder session capability: no persistent CLI session to manage (ACP
/// sessions live in the app-owned transcript) + the standard CONFIG_DIR
/// layout, pointed at `QODER_CONFIG_DIR` by the ACP capability.
final class QoderCliSessionCapability extends NoopCliSessionCapability {
  const QoderCliSessionCapability();
}

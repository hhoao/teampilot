import '../cli_capability.dart';

/// How a CLI consumes the teammate bus, which decides the **remote** transport
/// (P3b). CLIs that block in `wait_for_message` (a long-lived MCP call) need a
/// streaming relay over the reverse tunnel; doorbell-style CLIs (cursor) stop
/// at idle-at-prompt and are woken via stdin, so they only ever make short MCP
/// requests and can speak plain HTTP over the tunnel — no relay needed.
class BusTransportCapability implements CliCapability {
  const BusTransportCapability({required this.longBlockingWaitForMessage});

  /// True when the CLI parks in a long-blocking `wait_for_message` (claude,
  /// flashskyai, codex, opencode); false for doorbell CLIs (cursor).
  final bool longBlockingWaitForMessage;
}

import '../cli_capability.dart';

/// How TeamPilot drives a CLI process.
enum CliTransport {
  /// Interactive terminal: PTY plus argv assembled from launch contributions.
  pty,

  /// Agent Client Protocol over stdio (`cli --acp`, or an adapter binary).
  acp,
}

/// Which launch transports a CLI supports, and the one used when a launch
/// request does not pick a transport.
///
/// This is the single source of truth for transport availability: [supported]
/// containing [CliTransport.acp] must match the definition registering an
/// `AcpCapability` (asserted when the built-in registry is assembled).
///
/// A singleton `{acp}` set marks an ACP-only CLI (Gemini, CodeBuddy); call
/// sites read that through `CliToolRegistry.launchesAcpOnly` and must not
/// compare `CliTool` values.
final class CliTransportCapability implements CliCapability {
  const CliTransportCapability({
    required this.supported,
    CliTransport? defaultTransport,
  }) : _defaultTransport = defaultTransport;

  /// Transports this CLI can launch with. Declared as a const set literal on
  /// the tool definition (never mutated).
  final Set<CliTransport> supported;

  final CliTransport? _defaultTransport;

  bool supports(CliTransport transport) => supported.contains(transport);

  /// ACP when supported (the personal ACP preference default), otherwise PTY.
  ///
  /// Declare [defaultTransport] explicitly to override for a CLI that keeps
  /// PTY as its default despite speaking ACP.
  CliTransport get defaultTransport =>
      _defaultTransport ??
      (supports(CliTransport.acp) ? CliTransport.acp : CliTransport.pty);

  /// True when ACP is the only launch mode (no PTY fallback).
  bool get acpOnly => supported.length == 1 && supports(CliTransport.acp);
}

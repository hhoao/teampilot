import '../../acp_adapter_locator.dart';
import '../../registry/installer/npm_installer_capability.dart';

/// In-app npm installer for the Claude ACP adapter
/// (`@agentclientprotocol/claude-agent-acp`).
///
/// The adapter is a separate binary from `claude`; this never touches
/// `ClaudeExecutableCapability.npmPackage`. Installs are user-initiated from
/// the Claude ACP settings row only — connect never installs.
final class ClaudeAcpAdapterInstaller extends NpmInstallerCapability {
  const ClaudeAcpAdapterInstaller();

  static const package = '@agentclientprotocol/claude-agent-acp';

  /// Install-job target id (kept distinct from any `CliTool.value`).
  static const jobTarget = 'adapter:claude-agent-acp';

  @override
  String get npmPackage => package;

  @override
  String get executableName => 'claude-agent-acp';

  @override
  String get displayName => 'Claude ACP adapter';
}

/// Resolves the adapter binary without installing anything.
///
/// Order: an absolute match on `PATH`, then `~/.local/bin`, then the
/// TeamPilot node prefix (`$HOME/.local/share/<app-data>/toolchain/node/current/bin`
/// — in-app npm installs land here), else the bare name (so a missing adapter
/// still fails closed at spawn with `acpLaunchFailedAdapter`).
String locateClaudeAcpAdapter({
  Map<String, String>? environment,
  bool Function(String path)? fileExists,
  bool? isWindows,
}) {
  return locateAcpAdapter(
    name: 'claude-agent-acp',
    environment: environment,
    fileExists: fileExists,
    isWindows: isWindows,
  );
}

import 'dart:io';

import '../../../storage/app_paths.dart';
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
  const name = 'claude-agent-acp';
  if (isWindows ?? Platform.isWindows) return name;
  final env = environment ?? Platform.environment;
  final exists = fileExists ?? (path) => File(path).existsSync();

  final pathEntries = (env['PATH'] ?? '').split(':');
  for (final dir in pathEntries) {
    if (dir.isEmpty) continue;
    if (exists('$dir/$name')) return '$dir/$name';
  }
  final home = env['HOME'];
  if (home != null && home.isNotEmpty) {
    final local = '$home/.local/bin/$name';
    if (exists(local)) return local;
    final toolchain =
        '$home/.local/share/${AppPaths.teampilotAppDataDirName}/toolchain/node/current/bin/$name';
    if (exists(toolchain)) return toolchain;
  }
  return name;
}

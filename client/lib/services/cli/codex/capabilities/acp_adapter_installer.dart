import 'dart:io';

import '../../../storage/app_paths.dart';
import '../../registry/installer/npm_installer_capability.dart';

/// In-app npm installer for the Codex ACP adapter
/// (`@agentclientprotocol/codex-acp`).
///
/// The adapter is a separate binary from `codex`; this never touches
/// `CodexExecutableCapability.npmPackage`. Installs are user-initiated from
/// the Codex ACP settings row only — connect never installs.
final class CodexAcpAdapterInstaller extends NpmInstallerCapability {
  const CodexAcpAdapterInstaller();

  static const package = '@agentclientprotocol/codex-acp';

  /// Install-job target id (kept distinct from any `CliTool.value`).
  static const jobTarget = 'adapter:codex-acp';

  @override
  String get npmPackage => package;

  @override
  String get executableName => 'codex-acp';

  @override
  String get displayName => 'Codex ACP adapter';
}

/// Resolves the adapter binary without installing anything.
///
/// Order: an absolute match on `PATH`, then `~/.local/bin`, then the
/// TeamPilot node prefix (`$HOME/.local/share/<app-data>/toolchain/node/current/bin`
/// — in-app npm installs land here), else the bare name (so a missing adapter
/// still fails closed at spawn with `acpLaunchFailedAdapter`).
String locateCodexAcpAdapter({
  Map<String, String>? environment,
  bool Function(String path)? fileExists,
  bool? isWindows,
}) {
  const name = 'codex-acp';
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

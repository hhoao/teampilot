import '../../models/extension_manifest.dart';
import '../cli/installer_types.dart';
import 'extension_detector.dart';

typedef ExtensionInstallRunner = Future<CliInstallerCommandResult> Function(
  CliInstallerCommand command,
);

class ExtensionInstallResult {
  const ExtensionInstallResult({
    required this.success,
    this.message = '',
    this.version,
  });

  final bool success;
  final String message;
  final String? version;
}

/// Installs/uninstalls an extension's underlying tool on the local host by
/// mapping `acquire.kind`(+`alternatives`) to a shell command. Desktop/local
/// only in Phase 2 (no SSH/remote).
class ExtensionAcquisitionEngine {
  ExtensionAcquisitionEngine({
    required ExtensionInstallRunner runner,
    ExtensionDetector? detector,
  })  : _runner = runner,
        _detector = detector ?? ExtensionDetector();

  final ExtensionInstallRunner _runner;
  final ExtensionDetector _detector;

  Future<ExtensionInstallResult> install(ExtensionManifest manifest) async {
    final acquire = manifest.acquire;
    if (acquire == null || acquire.kind == 'none') {
      return const ExtensionInstallResult(
        success: false,
        message: 'No installer is defined for this extension.',
      );
    }

    final commands = _installCommands(acquire);
    if (commands.isEmpty) {
      return const ExtensionInstallResult(
        success: false,
        message: 'No installable target for this extension.',
      );
    }

    CliInstallerCommandResult? last;
    for (final command in commands) {
      last = await _runner(command);
      if (last.exitCode == 0) {
        final probe = await _detector.probe(manifest.detect);
        return ExtensionInstallResult(
          success: probe.found,
          version: probe.version,
          message: probe.found
              ? 'Installed.'
              : 'Install command succeeded but the tool was not found on PATH.',
        );
      }
    }
    return ExtensionInstallResult(
      success: false,
      message: last?.stderr.trim().isNotEmpty == true
          ? last!.stderr.trim()
          : 'Installation failed.',
    );
  }

  Future<ExtensionInstallResult> uninstall(ExtensionManifest manifest) async {
    final acquire = manifest.acquire;
    if (acquire == null) {
      return const ExtensionInstallResult(success: false, message: 'No installer.');
    }
    final command = _uninstallCommand(acquire);
    if (command == null) {
      return const ExtensionInstallResult(
        success: false,
        message: 'Uninstall is not supported for this install kind.',
      );
    }
    final result = await _runner(command);
    return ExtensionInstallResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'Uninstalled.' : result.stderr.trim(),
    );
  }

  /// Primary command for [acquire], then one per `alternatives` entry
  /// (`"<kind>:<arg>"`).
  List<CliInstallerCommand> _installCommands(ExtensionAcquireSpec acquire) {
    final commands = <CliInstallerCommand>[];
    final primary = _commandForKind(acquire.kind, acquire.package);
    if (primary != null) commands.add(primary);
    for (final alt in acquire.alternatives) {
      final idx = alt.indexOf(':');
      if (idx <= 0) continue;
      final kind = alt.substring(0, idx);
      final arg = alt.substring(idx + 1);
      final cmd = _commandForKind(kind, arg);
      if (cmd != null) commands.add(cmd);
    }
    return commands;
  }

  CliInstallerCommand? _commandForKind(String kind, String? arg) {
    final target = arg?.trim() ?? '';
    if (target.isEmpty && kind != 'none') return null;
    switch (kind) {
      case 'node-package':
        return CliInstallerCommand('npm', ['install', '-g', target]);
      case 'cargo':
        return CliInstallerCommand('cargo', ['install', target]);
      case 'brew':
        return CliInstallerCommand('brew', ['install', target]);
      case 'script':
        return CliInstallerCommand('sh', ['-c', 'curl -fsSL "$target" | sh']);
      default:
        return null;
    }
  }

  CliInstallerCommand? _uninstallCommand(ExtensionAcquireSpec acquire) {
    final target = acquire.package?.trim() ?? '';
    if (target.isEmpty) return null;
    switch (acquire.kind) {
      case 'node-package':
        return CliInstallerCommand('npm', ['uninstall', '-g', target]);
      case 'cargo':
        return CliInstallerCommand('cargo', ['uninstall', target]);
      case 'brew':
        return CliInstallerCommand('brew', ['uninstall', target]);
      default:
        return null;
    }
  }
}

import '../../models/session_preferences.dart';
import 'cli_tool_locator.dart';
import 'git_installer.dart';
import 'remote_cli_locator.dart';

typedef GitDetect = Future<GitInstallResult> Function();

/// Locates toolchain executables (git, node) on the local and remote host.
class ToolchainExecutableDiscovery {
  ToolchainExecutableDiscovery({
    GitInstaller? gitInstaller,
    GitDetect? detectGit,
    ProcessRunner? processRunner,
  }) : _detectGit =
           detectGit ?? (gitInstaller ?? const GitInstaller()).detectGit,
       _processRunner = processRunner ?? cliToolDefaultProcessRun;

  final GitDetect _detectGit;
  final ProcessRunner _processRunner;

  Future<Map<String, String>> locateLocal() async {
    final located = <String, String>{};

    final git = await _detectGit();
    final gitPath = git.executablePath?.trim() ?? '';
    if (git.success && gitPath.isNotEmpty) {
      located[SessionPreferences.toolchainGit] = gitPath;
    }

    final node = await CliToolLocator('node').locate(
      runner: _processRunner,
      includeShellFallback: true,
    );
    final nodePath = node?.trim() ?? '';
    if (nodePath.isNotEmpty) {
      located[SessionPreferences.toolchainNode] = nodePath;
    }

    return located;
  }

  Future<String?> locateLocalTool(String toolId) async {
    if (toolId == SessionPreferences.toolchainGit) {
      final git = await _detectGit();
      final gitPath = git.executablePath?.trim() ?? '';
      if (git.success && gitPath.isNotEmpty) return gitPath;
      return null;
    }
    if (toolId == SessionPreferences.toolchainNode) {
      final node = await CliToolLocator('node').locate(
        runner: _processRunner,
        includeShellFallback: true,
      );
      final nodePath = node?.trim() ?? '';
      return nodePath.isEmpty ? null : nodePath;
    }
    return null;
  }

  Future<String?> locateRemoteTool({
    required String toolId,
    required SshCommandRunner run,
  }) async {
    final name = switch (toolId) {
      SessionPreferences.toolchainGit => 'git',
      SessionPreferences.toolchainNode => 'node',
      _ => null,
    };
    if (name == null) return null;
    return DefaultRemoteCliLocator(name).locate(run);
  }
}

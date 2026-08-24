import 'dart:io' show Platform;

import '../../../../models/ssh_profile.dart';
import '../../../host/host_script_dialect.dart';
import '../../../host/host_script_runner.dart';
import '../../../storage/app_storage.dart';
import '../../cli_tool_locator.dart';
import '../../installer_types.dart';
import 'installer_context.dart';
import 'unix_node_bootstrap_strategy.dart';

/// Shared TeamPilot-managed Node.js bootstrap under app data (local + SSH).
///
/// Unix: `$HOME/.local/share/com.hhoa.teampilot/toolchain/node/<version>/`
/// Windows: `%LOCALAPPDATA%\com.hhoa.teampilot\toolchain\node\<version>\`
///
/// Remote Unix hosts use [UnixNodeBootstrapComposer] strategies (Termux pkg,
/// then glibc tarball). Attach via [CliInstallContext.node] so any
/// [CliExecutableCapability] can reuse the same version, paths, and npm resolution.
final class TeampilotNodeInstall {
  const TeampilotNodeInstall();

  static const standard = TeampilotNodeInstall();

  static const version = 'v24.15.0';

  /// Older Linux (glibc &lt; 2.28, e.g. CentOS 7) cannot run official Node 24.
  /// Unofficial glibc-2.17 builds stop at Node 22 — still fine for Claude Code.
  static const legacyGlibcVersion = 'v22.23.1';

  static const _appDataDirName = AppPaths.teampilotAppDataDirName;

  static const _cancelledResult = CliInstallerCommandResult(
    exitCode: -1,
    stderr: 'Cancelled',
  );

  /// `$HOME/.local/share/com.hhoa.teampilot/toolchain/node` for shell scripts.
  static String get unixToolchainNodeBase =>
      r'$HOME/.local/share/' + _appDataDirName + r'/toolchain/node';

  /// Remote Unix npm after bootstrap (`npm install -g` argv0).
  /// Uses the `current` symlink so glibc fallback versions resolve correctly.
  static String get bootstrappedUnixNpmPath =>
      '$unixToolchainNodeBase/current/bin/npm';

  /// `com.hhoa.teampilot\toolchain\node` under `%LOCALAPPDATA%`.
  static String get windowsToolchainNodeBase =>
      '$_appDataDirName\\toolchain\\node';

  /// Resolves local npm, bootstrapping Node when missing.
  Future<LocalNpmResolution> resolveLocalNpm(CliInstallerHost host) async {
    final existing = await host.locateLocalNpm();
    if (existing != null) {
      return LocalNpmFound(existing);
    }

    if (host.isCancelled) {
      return LocalNpmBootstrapFailed(_cancelledResult);
    }

    final bootstrap = await host.runLocal(
      localBootstrapCommand(host.scriptRunner),
      phase: CliInstallPhase.bootstrappingNode,
      streamOutput: true,
    );
    if (bootstrap.exitCode != 0) {
      return LocalNpmBootstrapFailed(bootstrap);
    }
    return const LocalNpmBootstrapped();
  }

  /// Resolves remote npm command, bootstrapping Node when missing.
  Future<RemoteNpmResolution> resolveRemoteNpm(
    CliInstallerHost host,
    SshProfile profile,
  ) async {
    final existing = await host.locateRemoteNpm(profile);
    if (existing != null) {
      final check = await host.runSsh(
        profile,
        CliInstallerCommand.unixShellScript(
          '"$existing" --version >/dev/null 2>&1',
        ),
      );
      if (check.exitCode == 0) {
        return RemoteNpmFound(existing);
      }
    }

    if (host.isCancelled) {
      return RemoteNpmBootstrapFailed(_cancelledResult);
    }

    host.report(CliInstallPhase.bootstrappingNode);
    final bootstrap = await host.runSsh(profile, sshBootstrapCommand());
    if (bootstrap.exitCode != 0) {
      return RemoteNpmBootstrapFailed(bootstrap);
    }
    // Termux pkg installs put npm under $PREFIX/bin (often linked into
    // ~/.local/bin by the bootstrap). Prefer a live locate over the glibc
    // toolchain path, which Termux never creates.
    final after = await host.locateRemoteNpm(profile);
    if (after != null) {
      return RemoteNpmFound(after);
    }
    return RemoteNpmFound(bootstrappedUnixNpmPath);
  }

  CliInstallerCommand localBootstrapCommand(HostScriptRunner runner) {
    final body = switch (runner.dialect) {
      HostScriptDialect.bash => _unixBootstrapScript(),
      HostScriptDialect.powershell => _windowsBootstrapScript(),
    };
    return runner.installerCommandForInline(body);
  }

  CliInstallerCommand sshBootstrapCommand() =>
      CliInstallerCommand.unixShellScript(_unixBootstrapScript());

  /// After [LocalNpmBootstrapped], install a global npm [package] locally.
  CliInstallerCommand bootstrappedLocalPackageInstall({
    required HostScriptRunner runner,
    required String package,
  }) {
    final body = switch (runner.dialect) {
      HostScriptDialect.powershell =>
        "& (Join-Path \$env:LOCALAPPDATA '$windowsToolchainNodeBase\\$version\\npm.cmd') install -g $package",
      HostScriptDialect.bash =>
        'export PATH="$unixToolchainNodeBase/current/bin:\$HOME/.local/bin:\$PATH"\n'
            'npm install -g --prefix "\$HOME/.local" $package',
    };
    return runner.installerCommandForInline(body);
  }

  /// Install [package] with an existing npm executable path.
  ///
  /// On macOS, uses the user's npm global prefix (Homebrew / nvm) so CLIs are
  /// available in Terminal. Linux and SSH keep one-shot `--prefix ~/.local`.
  CliInstallerCommand existingNpmPackageInstall({
    required bool isWindows,
    required String npmPath,
    required String package,
  }) {
    if (isWindows) {
      final spawnPath = CliToolLocator.resolveSpawnExecutable(npmPath);
      if (spawnPath.contains(r'\') || spawnPath.contains(':')) {
        return CliInstallerCommand('cmd', [
          '/c',
          spawnPath,
          'install',
          '-g',
          package,
        ]);
      }
      return CliInstallerCommand('cmd', [
        '/c',
        'npm',
        'install',
        '-g',
        package,
      ]);
    }
    if (Platform.isMacOS) {
      return _unixSystemNpmGlobalInstall(npmPath: npmPath, package: package);
    }
    return CliInstallerCommand.npmGlobalInstall(
      npmCommand: npmPath,
      package: package,
    );
  }

  /// `npm install -g` under the active npm prefix (no `~/.local` override).
  static CliInstallerCommand _unixSystemNpmGlobalInstall({
    required String npmPath,
    required String package,
  }) {
    final npm = CliToolLocator.resolveSpawnExecutable(npmPath);
    if (!CliInstallerCommand.needsUnixShellInvocation(npm) && npm.contains('/')) {
      return CliInstallerCommand(npm, ['install', '-g', package]);
    }
    if (CliInstallerCommand.needsUnixShellInvocation(npm)) {
      final binDir = npm.replaceAll(RegExp(r'/npm$'), '');
      return CliInstallerCommand.unixShellScript(
        'export PATH="$binDir:\$PATH"\n'
        'npm install -g $package',
      );
    }
    return CliInstallerCommand.unixShellScript('$npm install -g $package');
  }

  static String _unixBootstrapScript({
    List<UnixNodeBootstrapStrategy>? strategies,
  }) {
    return UnixNodeBootstrapComposer.compose(
      version: version,
      legacyGlibcVersion: legacyGlibcVersion,
      toolchainBase: unixToolchainNodeBase,
      strategies: strategies,
    );
  }

  static String _windowsBootstrapScript() {
    final base = windowsToolchainNodeBase;
    return '''
\$ErrorActionPreference = 'Stop'
\$version = '$version'
\$arch = if ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
\$base = Join-Path \$env:LOCALAPPDATA '$base'
\$target = Join-Path \$base \$version
\$archive = "node-\$version-win-\$arch.zip"
\$urls = @(
  "https://nodejs.org/dist/\$version/\$archive",
  "https://npmmirror.com/mirrors/node/\$version/\$archive"
)
\$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path \$base, \$tmp | Out-Null
try {
  \$archivePath = Join-Path \$tmp \$archive
  \$downloaded = \$false
  foreach (\$url in \$urls) {
    for (\$attempt = 1; \$attempt -le 5; \$attempt++) {
      try {
        Write-Host "Downloading Node.js from \$url (attempt \$attempt)"
        Invoke-WebRequest -Uri \$url -OutFile \$archivePath
        \$downloaded = \$true
        break
      } catch {
        Start-Sleep -Seconds 2
      }
    }
    if (\$downloaded) { break }
  }
  if (-not \$downloaded) { throw "Failed to download Node.js archive after retries" }
  if (Test-Path \$target) { Remove-Item -Recurse -Force \$target }
  Expand-Archive -Path \$archivePath -DestinationPath \$tmp -Force
  Move-Item -Path (Join-Path \$tmp "node-\$version-win-\$arch") -Destination \$target
  & (Join-Path \$target 'npm.cmd') --version
} finally {
  Remove-Item -Recurse -Force \$tmp -ErrorAction SilentlyContinue
}
''';
  }
}

sealed class LocalNpmResolution {
  const LocalNpmResolution();
}

final class LocalNpmFound extends LocalNpmResolution {
  const LocalNpmFound(this.npmPath);
  final String npmPath;
}

final class LocalNpmBootstrapped extends LocalNpmResolution {
  const LocalNpmBootstrapped();
}

final class LocalNpmBootstrapFailed extends LocalNpmResolution {
  const LocalNpmBootstrapFailed(this.result);
  final CliInstallerCommandResult result;
}

sealed class RemoteNpmResolution {
  const RemoteNpmResolution();
}

final class RemoteNpmFound extends RemoteNpmResolution {
  const RemoteNpmFound(this.npmCommand);
  final String npmCommand;
}

final class RemoteNpmBootstrapFailed extends RemoteNpmResolution {
  const RemoteNpmBootstrapFailed(this.result);
  final CliInstallerCommandResult result;
}

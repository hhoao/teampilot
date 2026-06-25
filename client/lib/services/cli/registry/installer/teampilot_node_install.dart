import '../../../../models/ssh_profile.dart';
import '../../../host/host_script_dialect.dart';
import '../../../host/host_script_runner.dart';
import '../../../storage/app_storage.dart';
import '../../cli_tool_locator.dart';
import '../../installer_types.dart';
import 'installer_context.dart';

/// Shared TeamPilot-managed Node.js bootstrap under app data (local + SSH).
///
/// Unix: `$HOME/.local/share/com.hhoa.teampilot/toolchain/node/<version>/`
/// Windows: `%LOCALAPPDATA%\com.hhoa.teampilot\toolchain\node\<version>\`
///
/// Attach via [CliInstallContext.node] so any [InstallerCapability] can reuse
/// the same version, paths, and npm resolution without duplicating scripts.
final class TeampilotNodeInstall {
  const TeampilotNodeInstall();

  static const standard = TeampilotNodeInstall();

  static const version = 'v24.15.0';

  static const _appDataDirName = AppPaths.teampilotAppDataDirName;

  /// `$HOME/.local/share/com.hhoa.teampilot/toolchain/node` for shell scripts.
  static String get unixToolchainNodeBase =>
      r'$HOME/.local/share/' + _appDataDirName + r'/toolchain/node';

  /// Remote Unix npm after bootstrap (`npm install -g` argv0).
  static String get bootstrappedUnixNpmPath =>
      '$unixToolchainNodeBase/$version/bin/npm';

  /// `com.hhoa.teampilot\toolchain\node` under `%LOCALAPPDATA%`.
  static String get windowsToolchainNodeBase =>
      '$_appDataDirName\\toolchain\\node';

  /// Resolves local npm, bootstrapping Node when missing.
  Future<LocalNpmResolution> resolveLocalNpm(CliInstallerHost host) async {
    final existing = await host.locateLocalNpm();
    if (existing != null) {
      return LocalNpmFound(existing);
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
      return RemoteNpmFound(existing);
    }

    host.report(CliInstallPhase.bootstrappingNode);
    final bootstrap = await host.runSsh(
      profile,
      sshBootstrapCommand(),
    );
    if (bootstrap.exitCode != 0) {
      return RemoteNpmBootstrapFailed(bootstrap);
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
        'export PATH="$unixToolchainNodeBase/$version/bin:\$HOME/.local/bin:\$PATH"\n'
        'npm config set prefix "\$HOME/.local"\n'
        'npm install -g $package',
    };
    return runner.installerCommandForInline(body);
  }

  /// Install [package] with an existing npm executable path.
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
    return CliInstallerCommand.npmGlobalInstall(
      npmCommand: npmPath,
      package: package,
    );
  }

  static String _unixBootstrapScript() {
    final base = unixToolchainNodeBase;
    return '''
set -e
os="\$(uname -s)"
arch="\$(uname -m)"
case "\$os" in
  Linux) platform="linux" ;;
  Darwin) platform="darwin" ;;
  *) echo "Unsupported OS: \$os" >&2; exit 2 ;;
esac
case "\$arch" in
  x86_64|amd64) node_arch="x64" ;;
  aarch64|arm64) node_arch="arm64" ;;
  *) echo "Unsupported architecture: \$arch" >&2; exit 2 ;;
esac
version="$version"
base="$base"
target="\$base/\$version"
archive="node-\$version-\$platform-\$node_arch.tar.xz"
url="https://nodejs.org/dist/\$version/\$archive"
mkdir -p "\$base" "\$HOME/.local/bin"
tmp="\$(mktemp -d)"
cleanup() { rm -rf "\$tmp"; }
trap cleanup EXIT
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "\$url" -o "\$tmp/\$archive"
elif command -v wget >/dev/null 2>&1; then
  wget -q "\$url" -O "\$tmp/\$archive"
else
  echo "curl or wget is required to download Node.js" >&2
  exit 3
fi
tar -xJf "\$tmp/\$archive" -C "\$tmp"
rm -rf "\$target"
mv "\$tmp/node-\$version-\$platform-\$node_arch" "\$target"
ln -sf "\$target/bin/node" "\$HOME/.local/bin/node"
ln -sf "\$target/bin/npm" "\$HOME/.local/bin/npm"
ln -sf "\$target/bin/npx" "\$HOME/.local/bin/npx"
PATH="\$target/bin:\$HOME/.local/bin:\$PATH" npm config set prefix "\$HOME/.local"
PATH="\$target/bin:\$HOME/.local/bin:\$PATH" npm --version
''';
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
\$url = "https://nodejs.org/dist/\$version/\$archive"
\$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path \$base, \$tmp | Out-Null
try {
  Invoke-WebRequest -Uri \$url -OutFile (Join-Path \$tmp \$archive)
  if (Test-Path \$target) { Remove-Item -Recurse -Force \$target }
  Expand-Archive -Path (Join-Path \$tmp \$archive) -DestinationPath \$tmp -Force
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

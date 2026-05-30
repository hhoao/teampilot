import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import 'cli_tool_locator.dart';
import 'registry/built_in_cli_tools.dart';
import 'registry/capabilities/installer_capability.dart';
import 'registry/cli_tool_registry.dart';
import '../ssh/ssh_client_factory.dart';

enum CliInstallMode { local, ssh }

enum CliInstallPhase {
  checkingNpm,
  bootstrappingNode,
  installingClaude,
  locatingExecutable,
}

class CliInstallProgress {
  const CliInstallProgress({required this.phase, this.detail});

  final CliInstallPhase phase;
  final String? detail;
}

class CliInstallerCommand {
  const CliInstallerCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  String get commandLine => [
    executable,
    ...arguments.map(_shellQuoteIfNeeded),
  ].join(' ');

  static String _shellQuoteIfNeeded(String value) {
    if (value.isEmpty) return "''";
    if (!value.contains(RegExp(r'\s'))) return value;
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }
}

class CliInstallerCommandResult {
  const CliInstallerCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  String get output {
    final text = [stdout.trim(), stderr.trim()]
        .where((value) => value.isNotEmpty)
        .join('\n');
    return text;
  }
}

class CliInstallResult {
  const CliInstallResult({
    required this.success,
    required this.message,
    this.executablePath,
  });

  final bool success;
  final String message;
  final String? executablePath;
}

typedef LocalCliInstallRunner =
    Future<CliInstallerCommandResult> Function(CliInstallerCommand command);
typedef SshCliInstallRunner =
    Future<CliInstallerCommandResult> Function(
      SshProfile profile,
      CliInstallerCommand command,
    );

typedef CliInstallProgressCallback = void Function(CliInstallProgress progress);

class CliInstallerService {
  CliInstallerService({
    LocalCliInstallRunner? localRunner,
    SshCliInstallRunner? sshRunner,
    SshClientFactory? sshClientFactory,
    bool? isWindowsOverride,
    CliToolRegistry? cliToolRegistry,
  }) : _localRunner = localRunner ?? _runLocal,
       _sshRunner = sshRunner ?? _SshCommandRunner(sshClientFactory).run,
       _isWindows = isWindowsOverride ?? Platform.isWindows,
       _cliToolRegistry = cliToolRegistry ?? _defaultCliRegistry;

  static final _defaultCliRegistry = () {
    final r = CliToolRegistry();
    registerBuiltInCliTools(r);
    return r;
  }();

  static const nodeVersion = 'v24.15.0';
  static const _claudePackage = '@anthropic-ai/claude-code';
  static const _bootstrappedNpmPath =
      r'$HOME/.local/share/teampilot/node/v24.15.0/bin/npm';

  final LocalCliInstallRunner _localRunner;
  final SshCliInstallRunner _sshRunner;
  final bool _isWindows;
  final CliToolRegistry _cliToolRegistry;
  CliInstallProgressCallback? _onProgress;

  Future<CliInstallResult> install({
    required TeamCli cli,
    required CliInstallMode mode,
    SshProfile? sshProfile,
    CliInstallProgressCallback? onProgress,
  }) async {
    _onProgress = onProgress;
    try {
      final installer =
          _cliToolRegistry.capability<InstallerCapability>(cli.value);
      if (installer?.supportsInstaller != true) {
        return const CliInstallResult(
          success: false,
          message: 'Only Claude Code installation is supported.',
        );
      }
      return switch (mode) {
        CliInstallMode.local => await _installLocal(),
        CliInstallMode.ssh => await _installSsh(sshProfile),
      };
    } finally {
      _onProgress = null;
    }
  }

  void _report(CliInstallPhase phase, {String? detail}) {
    _onProgress?.call(CliInstallProgress(phase: phase, detail: detail));
  }

  Future<CliInstallerCommandResult> _runLocalTracked(
    CliInstallerCommand command, {
    required CliInstallPhase phase,
    bool streamOutput = false,
  }) async {
    _report(phase);
    final useStreaming =
        streamOutput && _onProgress != null && identical(_localRunner, _runLocal);
    if (useStreaming) {
      return _runLocalStreaming(
        command,
        onOutput: (line) => _report(phase, detail: line),
      );
    }
    return _localRunner(command);
  }

  Future<CliInstallResult> _installLocal() async {
    _report(CliInstallPhase.checkingNpm);
    final npmPath = await _locateLocalNpm();
    late final CliInstallerCommand installCommand;
    if (npmPath == null) {
      final bootstrap = await _runLocalTracked(
        _localNodeBootstrapCommand(),
        phase: CliInstallPhase.bootstrappingNode,
        streamOutput: true,
      );
      if (bootstrap.exitCode != 0) {
        return CliInstallResult(
          success: false,
          message: _failureMessage('Local Node/npm install failed', bootstrap),
        );
      }
      installCommand = _bootstrappedLocalInstallCommand();
    } else {
      installCommand = _localNpmInstallCommand(npmPath);
    }

    final install = await _runLocalTracked(
      installCommand,
      phase: CliInstallPhase.installingClaude,
      streamOutput: true,
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: _failureMessage('Claude Code install failed', install),
      );
    }

    _report(CliInstallPhase.locatingExecutable);
    final path = await _locateLocalExecutable('claude');
    return CliInstallResult(
      success: true,
      message: 'Claude Code installed.',
      executablePath: path,
    );
  }

  Future<CliInstallResult> _installSsh(SshProfile? profile) async {
    if (profile == null) {
      return const CliInstallResult(
        success: false,
        message: 'Select an SSH server before installing Claude Code remotely.',
      );
    }

    _report(CliInstallPhase.checkingNpm);
    var npmCommand = await _locateRemoteNpm(profile);
    if (npmCommand == null) {
      _report(CliInstallPhase.bootstrappingNode);
      final bootstrap = await _sshRunner(
        profile,
        CliInstallerCommand('sh', ['-c', _unixNodeBootstrapScript()]),
      );
      if (bootstrap.exitCode != 0) {
        return CliInstallResult(
          success: false,
          message: _failureMessage('Remote Node/npm install failed', bootstrap),
        );
      }
      npmCommand = _bootstrappedNpmPath;
    }

    _report(CliInstallPhase.installingClaude);
    final install = await _sshRunner(
      profile,
      CliInstallerCommand(npmCommand, ['install', '-g', _claudePackage]),
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: _failureMessage('Remote Claude Code install failed', install),
      );
    }

    _report(CliInstallPhase.locatingExecutable);
    final resolved = await _sshRunner(
      profile,
      const CliInstallerCommand('command', ['-v', 'claude']),
    );
    final path = _firstOutputLine(resolved);
    return CliInstallResult(
      success: true,
      message: 'Claude Code installed on ${profile.hostIdentifier}.',
      executablePath: path,
    );
  }

  /// Resolves npm on the host. GUI-launched apps often have a sparse PATH, so
  /// [CliToolLocator] login-shell fallback and well-known paths are tried
  /// before bootstrapping Node from nodejs.org.
  Future<String?> _locateLocalNpm() async {
    return const CliToolLocator('npm').locate(
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        final result = await _localRunner(
          CliInstallerCommand(executable, arguments),
        );
        return ProcessResult(
          -1,
          result.exitCode,
          result.stdout,
          result.stderr,
        );
      },
      isWindowsOverride: _isWindows,
    ).then((located) {
      if (located != null) return located;
      // Tests inject [localRunner]; skip macOS well-known-path probe so CI
      // runners with Homebrew npm do not bypass mocked command flows.
      if (!identical(_localRunner, _runLocal)) return null;
      return _firstExistingUnixNpmPath();
    });
  }

  Future<String?> _locateRemoteNpm(SshProfile profile) async {
    final direct = await _sshRunner(
      profile,
      const CliInstallerCommand('command', ['-v', 'npm']),
    );
    final fromDirect = _firstOutputLine(direct);
    if (fromDirect != null) return fromDirect;

    for (final shell in const ['bash', 'zsh']) {
      final viaShell = await _sshRunner(
        profile,
        CliInstallerCommand(shell, ['-ilc', 'command -v npm']),
      );
      final fromShell = _firstOutputLine(viaShell);
      if (fromShell != null) return fromShell;
    }
    return null;
  }

  static String? _firstExistingUnixNpmPath() {
    if (Platform.isWindows || !Platform.isMacOS) return null;
    final home = Platform.environment['HOME'];
    final candidates = <String>[
      '/opt/homebrew/bin/npm',
      '/usr/local/bin/npm',
      if (home != null) '$home/.local/bin/npm',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  CliInstallerCommand _localNodeBootstrapCommand() {
    if (_isWindows) {
      return CliInstallerCommand(
        'powershell',
        ['-NoProfile', '-Command', _windowsNodeBootstrapScript()],
      );
    }
    // Non-login shell: avoid sourcing /etc/profile (blocked for some GUI apps).
    return CliInstallerCommand('sh', ['-c', _unixNodeBootstrapScript()]);
  }

  CliInstallerCommand _localNpmInstallCommand(String npmPath) {
    if (_isWindows) {
      final spawnPath = CliToolLocator.resolveSpawnExecutable(npmPath);
      if (spawnPath.contains(r'\') || spawnPath.contains(':')) {
        // Windows npm is a .cmd shim; invoke through cmd.exe so Process.run
        // can execute it reliably from a GUI-launched app.
        return CliInstallerCommand('cmd', [
          '/c',
          spawnPath,
          'install',
          '-g',
          _claudePackage,
        ]);
      }
      return CliInstallerCommand('cmd', [
        '/c',
        'npm',
        'install',
        '-g',
        _claudePackage,
      ]);
    }
    return CliInstallerCommand(npmPath, ['install', '-g', _claudePackage]);
  }

  CliInstallerCommand _bootstrappedLocalInstallCommand() {
    if (_isWindows) {
      return CliInstallerCommand('powershell', [
        '-NoProfile',
        '-Command',
        "& (Join-Path \$env:LOCALAPPDATA 'teampilot\\node\\$nodeVersion\\npm.cmd') install -g $_claudePackage",
      ]);
    }
    return CliInstallerCommand('sh', [
      '-c',
      '\$HOME/.local/share/teampilot/node/$nodeVersion/bin/npm install -g $_claudePackage',
    ]);
  }

  Future<String?> _locateLocalExecutable(String name) {
    return CliToolLocator(name).locate(
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
        final result = await _localRunner(
          CliInstallerCommand(executable, arguments),
        );
        return ProcessResult(
          -1,
          result.exitCode,
          result.stdout,
          result.stderr,
        );
      },
      isWindowsOverride: _isWindows,
    );
  }

  static Future<CliInstallerCommandResult> _runLocal(
    CliInstallerCommand command,
  ) async {
    try {
      final result = await Process.run(command.executable, command.arguments);
      return CliInstallerCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout?.toString() ?? '',
        stderr: result.stderr?.toString() ?? '',
      );
    } on ProcessException catch (e) {
      return CliInstallerCommandResult(exitCode: 127, stderr: e.message);
    }
  }

  static Future<CliInstallerCommandResult> _runLocalStreaming(
    CliInstallerCommand command, {
    void Function(String line)? onOutput,
  }) async {
    try {
      final process = await Process.start(
        command.executable,
        command.arguments,
      );
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      Future<void> drainStream(
        Stream<List<int>> stream,
        StringBuffer buffer,
      ) async {
        await stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((line) {
              buffer.writeln(line);
              final trimmed = line.trim();
              if (trimmed.isNotEmpty) {
                onOutput?.call(trimmed);
              }
            });
      }

      await Future.wait([
        drainStream(process.stdout, stdoutBuffer),
        drainStream(process.stderr, stderrBuffer),
      ]);
      final exitCode = await process.exitCode;
      return CliInstallerCommandResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
      );
    } on ProcessException catch (e) {
      return CliInstallerCommandResult(exitCode: 127, stderr: e.message);
    }
  }

  static String _unixNodeBootstrapScript() {
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
version="$nodeVersion"
base="\$HOME/.local/share/teampilot/node"
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
"\$target/bin/npm" --version
''';
  }

  static String _windowsNodeBootstrapScript() {
    return r'''
$ErrorActionPreference = 'Stop'
$version = 'v24.15.0'
$arch = if ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
$base = Join-Path $env:LOCALAPPDATA 'teampilot\node'
$target = Join-Path $base $version
$archive = "node-$version-win-$arch.zip"
$url = "https://nodejs.org/dist/$version/$archive"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $base, $tmp | Out-Null
try {
  Invoke-WebRequest -Uri $url -OutFile (Join-Path $tmp $archive)
  if (Test-Path $target) { Remove-Item -Recurse -Force $target }
  Expand-Archive -Path (Join-Path $tmp $archive) -DestinationPath $tmp -Force
  Move-Item -Path (Join-Path $tmp "node-$version-win-$arch") -Destination $target
  & (Join-Path $target 'npm.cmd') --version
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
''';
  }

  static String? _firstOutputLine(CliInstallerCommandResult result) {
    if (result.exitCode != 0) return null;
    final line = result.stdout.split('\n').first.trim();
    return line.isEmpty ? null : line;
  }

  static String _failureMessage(String title, CliInstallerCommandResult result) {
    final output = result.output;
    if (output.isEmpty) return '$title (exit ${result.exitCode}).';
    return '$title (exit ${result.exitCode}): $output';
  }
}

class _SshCommandRunner {
  const _SshCommandRunner(this._clientFactory);

  final SshClientFactory? _clientFactory;

  Future<CliInstallerCommandResult> run(
    SshProfile profile,
    CliInstallerCommand command,
  ) async {
    final factory = _clientFactory;
    if (factory == null) {
      return const CliInstallerCommandResult(
        exitCode: 1,
        stderr: 'SSH client is not available.',
      );
    }
    try {
      final client = await factory.clientFor(profile);
      final session = await client.execute(command.commandLine);
      final stdout = await _decode(session.stdout);
      final stderr = await _decode(session.stderr);
      await session.done;
      return CliInstallerCommandResult(
        exitCode: session.exitCode ?? 0,
        stdout: stdout,
        stderr: stderr,
      );
    } on Object catch (e) {
      return CliInstallerCommandResult(exitCode: 1, stderr: e.toString());
    }
  }

  static Future<String> _decode(Stream<Uint8List> stream) async {
    return utf8.decode(await stream.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    ));
  }
}

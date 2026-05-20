import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/ssh_profile.dart';
import '../models/team_config.dart';
import 'ssh_client_factory.dart';

enum CliInstallMode { local, ssh }

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

class CliInstallerService {
  CliInstallerService({
    LocalCliInstallRunner? localRunner,
    SshCliInstallRunner? sshRunner,
    SshClientFactory? sshClientFactory,
  }) : _localRunner = localRunner ?? _runLocal,
       _sshRunner = sshRunner ?? _SshCommandRunner(sshClientFactory).run;

  static const nodeVersion = 'v24.15.0';
  static const _claudePackage = '@anthropic-ai/claude-code';

  final LocalCliInstallRunner _localRunner;
  final SshCliInstallRunner _sshRunner;

  Future<CliInstallResult> install({
    required TeamCli cli,
    required CliInstallMode mode,
    SshProfile? sshProfile,
  }) async {
    if (cli != TeamCli.claude) {
      return const CliInstallResult(
        success: false,
        message: 'Only Claude Code installation is supported.',
      );
    }
    return switch (mode) {
      CliInstallMode.local => _installLocal(),
      CliInstallMode.ssh => _installSsh(sshProfile),
    };
  }

  Future<CliInstallResult> _installLocal() async {
    final install = await _localRunner(
      const CliInstallerCommand('npm', ['install', '-g', _claudePackage]),
    );
    if (install.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: _failureMessage('Claude Code install failed', install),
      );
    }
    final resolved = await _localRunner(
      const CliInstallerCommand('command', ['-v', 'claude']),
    );
    final path = _firstOutputLine(resolved);
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

    var npmCommand = 'npm';
    final npmProbe = await _sshRunner(
      profile,
      const CliInstallerCommand('command', ['-v', 'npm']),
    );
    if (npmProbe.exitCode != 0) {
      final bootstrap = await _sshRunner(
        profile,
        CliInstallerCommand('sh', ['-lc', _nodeBootstrapScript()]),
      );
      if (bootstrap.exitCode != 0) {
        return CliInstallResult(
          success: false,
          message: _failureMessage('Remote Node/npm install failed', bootstrap),
        );
      }
      npmCommand =
          r'$HOME/.local/share/teampilot/node/v24.15.0/bin/npm';
    }

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

  static String _nodeBootstrapScript() {
    return '''
set -e
arch="\$(uname -m)"
case "\$arch" in
  x86_64|amd64) node_arch="x64" ;;
  aarch64|arm64) node_arch="arm64" ;;
  *) echo "Unsupported architecture: \$arch" >&2; exit 2 ;;
esac
version="$nodeVersion"
base="\$HOME/.local/share/teampilot/node"
target="\$base/\$version"
archive="node-\$version-linux-\$node_arch.tar.xz"
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
mv "\$tmp/node-\$version-linux-\$node_arch" "\$target"
ln -sf "\$target/bin/node" "\$HOME/.local/bin/node"
ln -sf "\$target/bin/npm" "\$HOME/.local/bin/npm"
ln -sf "\$target/bin/npx" "\$HOME/.local/bin/npx"
"\$target/bin/npm" --version
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

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/claude/capabilities/executable.dart';
import 'package:teampilot/services/cli/cursor/capabilities/executable.dart';
import 'package:teampilot/services/cli/registry/installer/installer_context.dart';
import 'package:teampilot/services/cli/registry/installer/termux_remote_detect.dart';
import 'package:teampilot/services/cli/registry/installer/unix_node_bootstrap_strategy.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/host_script_runner.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

void main() {
  group('UnixNodeBootstrapComposer', () {
    test('default order is Termux then glibc tarball', () {
      final script = UnixNodeBootstrapComposer.compose(
        version: 'v24.15.0',
        legacyGlibcVersion: 'v22.23.1',
        toolchainBase: r'$HOME/.local/share/com.hhoa.teampilot/toolchain/node',
      );
      expect(script, contains('pkg install -y nodejs'));
      expect(script, contains('nodejs.org/dist/'));
      final termuxIdx = script.indexOf('pkg install -y nodejs');
      final extractIdx = script.indexOf(r'tar -xJf "$tmp/$archive"');
      expect(extractIdx, greaterThan(termuxIdx));
    });

    test('custom strategies replace the default chain', () {
      final script = UnixNodeBootstrapComposer.compose(
        version: 'v1',
        legacyGlibcVersion: 'v0',
        toolchainBase: r'$HOME/x',
        strategies: const [_FakeBootstrap()],
      );
      expect(script, contains('FAKE_BOOTSTRAP'));
      expect(script, isNot(contains('pkg install -y nodejs')));
      expect(script, isNot(contains('nodejs.org/dist/')));
    });
  });

  group('TermuxRemoteDetect', () {
    test('probe output parser', () {
      expect(TermuxRemoteDetect.isTermuxFromProbeOutput('TERMUX=1\n'), isTrue);
      expect(TermuxRemoteDetect.isTermuxFromProbeOutput('TERMUX=0\n'), isFalse);
    });
  });

  group('CursorExecutableCapability Termux', () {
    test('skips curl install on Termux when binary missing', () async {
      final host = _FakeHost(termux: true, locatePath: null);
      final result = await const CursorExecutableCapability().install(
        CliInstallContext(
          mode: CliInstallMode.ssh,
          host: host,
          hostEnvironment: HostExecutionEnvironment.resolve(
            isWindowsHost: false,
            storageMode: StorageBackendMode.native,
          ),
          sshProfile: const SshProfile(
            id: 'termux',
            name: 'Termux',
            host: '127.0.0.1',
            username: 'u0_a1',
          ),
        ),
      );
      expect(result.success, isFalse);
      expect(result.message, CursorExecutableCapability.termuxUnsupportedMessage);
      expect(host.ranCurlInstall, isFalse);
    });

    test('returns existing cursor-agent on Termux without curl', () async {
      final host = _FakeHost(
        termux: true,
        locatePath: '/data/data/com.termux/files/usr/bin/cursor-agent',
      );
      final result = await const CursorExecutableCapability().install(
        CliInstallContext(
          mode: CliInstallMode.ssh,
          host: host,
          hostEnvironment: HostExecutionEnvironment.resolve(
            isWindowsHost: false,
            storageMode: StorageBackendMode.native,
          ),
          sshProfile: const SshProfile(
            id: 'termux',
            name: 'Termux',
            host: '127.0.0.1',
            username: 'u0_a1',
          ),
        ),
      );
      expect(result.success, isTrue);
      expect(result.executablePath, host.locatePath);
      expect(host.ranCurlInstall, isFalse);
    });
  });

  group('CursorExecutableCapability glibc', () {
    test('skips curl install when remote glibc is below 2.28', () async {
      final host = _FakeHost(
        termux: false,
        locatePath: null,
        glibc: '2.17',
      );
      final result = await const CursorExecutableCapability().install(
        CliInstallContext(
          mode: CliInstallMode.ssh,
          host: host,
          hostEnvironment: HostExecutionEnvironment.resolve(
            isWindowsHost: false,
            storageMode: StorageBackendMode.native,
          ),
          sshProfile: const SshProfile(
            id: 'centos7',
            name: 'CentOS 7',
            host: '10.0.0.8',
            username: 'root',
          ),
        ),
      );
      expect(result.success, isFalse);
      expect(result.message, contains('glibc'));
      expect(result.message, contains('2.17'));
      expect(result.message, contains('2.28'));
      expect(host.ranCurlInstall, isFalse);
      expect(host.ranGlibcProbe, isTrue);
    });

    test('installs via curl when remote glibc is 2.28+', () async {
      final host = _FakeHost(
        termux: false,
        locatePath: '/root/.local/bin/cursor-agent',
        glibc: '2.28',
      );
      final result = await const CursorExecutableCapability().install(
        CliInstallContext(
          mode: CliInstallMode.ssh,
          host: host,
          hostEnvironment: HostExecutionEnvironment.resolve(
            isWindowsHost: false,
            storageMode: StorageBackendMode.native,
          ),
          sshProfile: const SshProfile(
            id: 'ubuntu',
            name: 'Ubuntu',
            host: '10.0.0.9',
            username: 'root',
          ),
        ),
      );
      expect(result.success, isTrue, reason: result.message);
      expect(result.executablePath, '/root/.local/bin/cursor-agent');
      expect(host.ranGlibcProbe, isTrue);
      expect(host.ranCurlInstall, isTrue);
    });
  });

  group('ClaudeExecutableCapability Termux', () {
    test('pinned install script targets 2.1.112 and disables auto-updater', () {
      final script = ClaudeExecutableCapability.termuxPinnedInstallScript();
      expect(script, contains(ClaudeExecutableCapability.termuxPinnedPackage));
      expect(script, contains('DISABLE_AUTOUPDATER=1'));
      expect(script, contains('npm uninstall'));
      expect(script, isNot(contains('@anthropic-ai/claude-code@latest')));
    });

    test('uses Termux pin path instead of @latest on Termux', () async {
      final host = _ClaudeFakeHost();
      final result = await const ClaudeExecutableCapability().install(
        CliInstallContext(
          mode: CliInstallMode.ssh,
          host: host,
          hostEnvironment: HostExecutionEnvironment.resolve(
            isWindowsHost: false,
            storageMode: StorageBackendMode.native,
          ),
          sshProfile: const SshProfile(
            id: 'termux',
            name: 'Termux',
            host: '127.0.0.1',
            username: 'u0_a1',
          ),
        ),
      );
      expect(result.success, isTrue);
      expect(result.executablePath, '/data/data/com.termux/files/usr/bin/claude');
      expect(result.message, contains('2.1.112'));
      expect(host.ranPinnedInstall, isTrue);
      expect(host.ranLatestNpmInstall, isFalse);
    });
  });
}

final class _FakeBootstrap implements UnixNodeBootstrapStrategy {
  const _FakeBootstrap();

  @override
  String buildScript() => 'echo FAKE_BOOTSTRAP\nexit 0\n';
}

final class _FakeHost implements CliInstallerHost {
  _FakeHost({required this.termux, required this.locatePath, this.glibc});

  final bool termux;
  final String? locatePath;
  final String? glibc;
  var ranCurlInstall = false;
  var ranGlibcProbe = false;

  @override
  HostExecutionEnvironment get hostEnvironment => HostExecutionEnvironment.resolve(
    isWindowsHost: false,
    storageMode: StorageBackendMode.native,
  );

  @override
  bool get isWindows => false;

  @override
  HostScriptRunner get scriptRunner => hostEnvironment.scriptRunner;

  @override
  void report(CliInstallPhase phase, {String? detail}) {}

  @override
  Future<CliInstallerCommandResult> runLocal(
    CliInstallerCommand command, {
    required CliInstallPhase phase,
    bool streamOutput = false,
  }) async => const CliInstallerCommandResult(exitCode: 1);

  @override
  Future<CliInstallerCommandResult> runSsh(
    SshProfile profile,
    CliInstallerCommand command,
  ) async {
    final line = command.commandLine;
    if (line.contains('TERMUX=')) {
      return CliInstallerCommandResult(
        exitCode: 0,
        stdout: termux ? 'TERMUX=1\n' : 'TERMUX=0\n',
      );
    }
    if (line.contains('ldd --version') && line.contains('GLIBC=')) {
      ranGlibcProbe = true;
      final version = glibc ?? '2.31';
      return CliInstallerCommandResult(
        exitCode: 0,
        stdout: 'GLIBC=$version\n',
      );
    }
    if (line.contains('curl') && line.contains('cursor.com/install')) {
      ranCurlInstall = true;
      return const CliInstallerCommandResult(exitCode: 0);
    }
    if (line.contains('cursor-agent') || line.contains('command -v')) {
      if (locatePath == null) {
        return const CliInstallerCommandResult(exitCode: 1);
      }
      return CliInstallerCommandResult(exitCode: 0, stdout: '$locatePath\n');
    }
    return const CliInstallerCommandResult(exitCode: 0);
  }

  @override
  Future<String?> locateExecutable(String name) async => null;

  @override
  Future<String?> locateLocalNpm() async => null;

  @override
  Future<String?> locateRemoteNpm(SshProfile profile) async => null;

  @override
  bool get isCancelled => false;
}

/// Termux Claude install host: npm already present; no working claude yet.
final class _ClaudeFakeHost implements CliInstallerHost {
  var ranPinnedInstall = false;
  var ranLatestNpmInstall = false;

  @override
  HostExecutionEnvironment get hostEnvironment => HostExecutionEnvironment.resolve(
    isWindowsHost: false,
    storageMode: StorageBackendMode.native,
  );

  @override
  bool get isWindows => false;

  @override
  HostScriptRunner get scriptRunner => hostEnvironment.scriptRunner;

  @override
  void report(CliInstallPhase phase, {String? detail}) {}

  @override
  Future<CliInstallerCommandResult> runLocal(
    CliInstallerCommand command, {
    required CliInstallPhase phase,
    bool streamOutput = false,
  }) async => const CliInstallerCommandResult(exitCode: 1);

  @override
  Future<CliInstallerCommandResult> runSsh(
    SshProfile profile,
    CliInstallerCommand command,
  ) async {
    final line = command.commandLine;
    if (line.contains('TERMUX=')) {
      return const CliInstallerCommandResult(exitCode: 0, stdout: 'TERMUX=1\n');
    }
    if (line.contains('2.1.112') || line.contains('DISABLE_AUTOUPDATER')) {
      ranPinnedInstall = true;
      return const CliInstallerCommandResult(
        exitCode: 0,
        stdout: '/data/data/com.termux/files/usr/bin/claude\n',
      );
    }
    if (line.contains('@anthropic-ai/claude-code') &&
        !line.contains('2.1.112')) {
      ranLatestNpmInstall = true;
    }
    if (line.contains('--version')) {
      return const CliInstallerCommandResult(exitCode: 0);
    }
    if (line.contains('command -v claude') ||
        line.contains("command -v \$executableName") ||
        (line.contains('claude') && line.contains('PREFIX'))) {
      // Pre-install locate: missing. Post-install locate: present.
      if (ranPinnedInstall) {
        return const CliInstallerCommandResult(
          exitCode: 0,
          stdout: '/data/data/com.termux/files/usr/bin/claude\n',
        );
      }
      return const CliInstallerCommandResult(exitCode: 1);
    }
    return const CliInstallerCommandResult(exitCode: 0);
  }

  @override
  Future<String?> locateExecutable(String name) async => null;

  @override
  Future<String?> locateLocalNpm() async => null;

  @override
  Future<String?> locateRemoteNpm(SshProfile profile) async =>
      '/data/data/com.termux/files/usr/bin/npm';

  @override
  bool get isCancelled => false;
}

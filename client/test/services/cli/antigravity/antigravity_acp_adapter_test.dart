import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/registry/installer/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/registry/installer/binary_archive_installer.dart';
import 'package:teampilot/services/cli/registry/installer/installer_context.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/host_script_runner.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

void main() {
  test('maps platform/arch to the pinned ACP asset key', () {
    expect(antigravityAcpAssetKey(os: 'linux', arch: 'x64'), 'linux-x86_64');
    expect(antigravityAcpAssetKey(os: 'linux', arch: 'arm64'), 'linux-aarch64');
    expect(antigravityAcpAssetKey(os: 'darwin', arch: 'x64'), 'darwin-x86_64');
    expect(
      antigravityAcpAssetKey(os: 'darwin', arch: 'arm64'),
      'darwin-aarch64',
    );
    expect(
      antigravityAcpAssetKey(os: 'windows', arch: 'x64'),
      'windows-x86_64',
    );
    expect(
      antigravityAcpAssetKey(os: 'windows', arch: 'arm64'),
      'windows-aarch64',
    );
  });

  test('exposes the neutral contract and pins the version', () {
    const installer = AntigravityAcpAdapterInstaller();
    expect(installer, isA<AcpAdapterInstaller>());
    expect(
      installer.adapterJobTarget,
      AntigravityAcpAdapterInstaller.jobTarget,
    );
    expect(
      installer.executableName,
      anyOf('agy_acp_server.par', 'agy_acp_server.exe'),
    );
    expect(installer.supportsInstaller, isTrue);
  });

  test('archive URL folder is macos for darwin, OS name otherwise', () {
    const base = 'https://dl.google.com/agy-extensions/releases';
    expect(
      antigravityAcpArchiveUrl('darwin-aarch64'),
      '$base/macos/agy-acp-server-1.4.3-darwin-aarch64.zip',
    );
    expect(
      antigravityAcpArchiveUrl('darwin-x86_64'),
      '$base/macos/agy-acp-server-1.4.3-darwin-x86_64.zip',
    );
    expect(
      antigravityAcpArchiveUrl('linux-x86_64'),
      '$base/linux/agy-acp-server-1.4.3-linux-x86_64.zip',
    );
    expect(
      antigravityAcpArchiveUrl('linux-aarch64'),
      '$base/linux/agy-acp-server-1.4.3-linux-aarch64.zip',
    );
    expect(
      antigravityAcpArchiveUrl('windows-aarch64'),
      '$base/windows/agy-acp-server-1.4.3-windows-aarch64.zip',
    );
  });

  test('every mappable asset key has a pinned sha256', () {
    for (final os in ['darwin', 'linux', 'windows']) {
      for (final arch in ['x64', 'arm64']) {
        final key = antigravityAcpAssetKey(os: os, arch: arch);
        final sha = antigravityAcpSha256[key];
        expect(sha, isNotNull, reason: 'missing sha256 for $key');
        expect(sha, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    }
  });

  test('executableName matches the pinned Unix/Windows adapter names', () {
    const installer = AntigravityAcpAdapterInstaller();
    expect(
      installer.executableName,
      Platform.isWindows ? 'agy_acp_server.exe' : 'agy_acp_server.par',
    );
    expect(
      installer.executableName,
      endsWith(Platform.isWindows ? '.exe' : '.par'),
    );
    expect(installer.latestVersion(), completion(antigravityAcpVersion));
  });

  test(
    'resolveInstalledPath is null without storage or without the file',
    () async {
      final root = await Directory.systemTemp.createTemp('agy-acp-resolve-');
      addTearDown(() => root.delete(recursive: true));
      const unconfigured = AntigravityAcpAdapterInstaller();
      expect(await unconfigured.resolveInstalledPath(), isNull);

      final storage = _storageAt(root.path);
      final installer = AntigravityAcpAdapterInstaller(storage: storage);
      expect(await installer.resolveInstalledPath(), isNull);

      final exe = File(
        storage.fs.pathContext.join(
          root.path,
          'toolchain',
          'antigravity-acp',
          antigravityAcpVersion,
          installer.executableName,
        ),
      );
      await exe.create(recursive: true);
      expect(await installer.resolveInstalledPath(), exe.path);
    },
  );

  test('ssh install returns a failure and never downloads', () async {
    final root = await Directory.systemTemp.createTemp('agy-acp-ssh-');
    addTearDown(() => root.delete(recursive: true));
    var fetched = false;
    final installer = AntigravityAcpAdapterInstaller(
      storage: _storageAt(root.path),
      binary: BinaryArchiveInstaller(
        fs: LocalFilesystem(),
        fetch: (uri, {expectedSha256, onProgress, isCancelled}) async {
          fetched = true;
          throw StateError('ssh install must not download');
        },
      ),
    );
    final host = _FakeHost();
    final result = await installer.install(
      CliInstallContext(
        mode: CliInstallMode.ssh,
        host: host,
        hostEnvironment: host.hostEnvironment,
        sshProfile: const SshProfile(
          id: 'p1',
          name: 'box',
          host: 'example.invalid',
          username: 'dev',
        ),
      ),
    );
    expect(result.success, isFalse);
    expect(result.executablePath, isNull);
    expect(fetched, isFalse);
    expect(host.reported, isEmpty);
    expect(Directory('${root.path}/toolchain').existsSync(), isFalse);
  });

  test('local install downloads the pinned asset plus the sidecar', () async {
    final root = await Directory.systemTemp.createTemp('agy-acp-local-');
    addTearDown(() => root.delete(recursive: true));
    final storage = _storageAt(root.path);
    final downloads = <Uri>[];
    final shas = <String?>[];
    final host = _FakeHost();
    final installer = AntigravityAcpAdapterInstaller(
      storage: storage,
      binary: BinaryArchiveInstaller(
        fs: LocalFilesystem(),
        fetch: (uri, {expectedSha256, onProgress, isCancelled}) async {
          downloads.add(uri);
          shas.add(expectedSha256);
          final file = File('${root.path}/fake.zip');
          await file.writeAsBytes(const [0]);
          return file;
        },
        extract: ({required archive, required destDir}) async {
          await Directory(destDir).create(recursive: true);
          for (final name in _hostExecutables) {
            await File('$destDir/$name').writeAsBytes(const [1]);
          }
        },
        chmod: (_) async {},
      ),
    );

    final result = await installer.install(
      CliInstallContext(
        mode: CliInstallMode.local,
        host: host,
        hostEnvironment: host.hostEnvironment,
      ),
    );

    expect(result.success, isTrue);
    final exe = result.executablePath;
    expect(exe, isNotNull);
    expect(exe, endsWith(installer.executableName));
    final destDir = storage.fs.pathContext.dirname(exe!);
    expect(
      destDir,
      endsWith(
        storage.fs.pathContext.join('antigravity-acp', antigravityAcpVersion),
      ),
    );
    for (final name in _hostExecutables) {
      expect(File('$destDir/$name').existsSync(), isTrue, reason: name);
    }
    expect(await installer.resolveInstalledPath(), exe);

    expect(downloads, hasLength(1));
    final url = downloads.single;
    final arch = Platform.version.contains('arm64') ? 'aarch64' : 'x86_64';
    final expectedKey = '$_hostOs-$arch';
    expect(url.host, 'dl.google.com');
    expect(url.pathSegments[2], Platform.isMacOS ? 'macos' : _hostOs);
    expect(
      url.pathSegments.last,
      'agy-acp-server-$antigravityAcpVersion-$expectedKey.zip',
    );
    expect(shas.single, antigravityAcpSha256[expectedKey]);
    expect(host.reported, contains(CliInstallPhase.installingCli));
  });
}

HomeStorage _storageAt(String root) => HomeStorage.forTesting(
  filesystem: LocalFilesystem(),
  paths: AppPaths(root),
);

String get _hostOs =>
    Platform.isWindows ? 'windows' : (Platform.isMacOS ? 'darwin' : 'linux');

/// The `.par` plus its `localharness_external` sidecar (probe 1.4.3: the
/// adapter cannot open a session without the sidecar next to it).
List<String> get _hostExecutables => [
  Platform.isWindows ? 'agy_acp_server.exe' : 'agy_acp_server.par',
  Platform.isWindows ? 'localharness_external.exe' : 'localharness_external',
];

final class _FakeHost implements CliInstallerHost {
  final reported = <CliInstallPhase>[];

  @override
  HostExecutionEnvironment get hostEnvironment =>
      HostExecutionEnvironment.resolve(
        isWindowsHost: false,
        storageMode: StorageBackendMode.native,
      );

  @override
  bool get isWindows => false;

  @override
  HostScriptRunner get scriptRunner => hostEnvironment.scriptRunner;

  @override
  void report(CliInstallPhase phase, {String? detail}) => reported.add(phase);

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
  ) async => const CliInstallerCommandResult(exitCode: 1);

  @override
  Future<String?> locateExecutable(String name) async => null;

  @override
  Future<String?> locateLocalNpm() async => null;

  @override
  Future<String?> locateRemoteNpm(SshProfile profile) async => null;

  @override
  bool get isCancelled => false;
}

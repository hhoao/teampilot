@Tags(['integration', 'docker'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/io/sftp_filesystem.dart';
import 'package:teampilot/services/remote/materialization_manifest.dart';
import 'package:teampilot/services/remote/work_machine_materializer.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/storage/remote_file_store.dart';

import 'support/docker_ssh_server.dart';

/// SftpFilesystem that counts file-content writes (ancestry copies), so the
/// manifest-hit behavior is observable over a real SSH/SFTP connection.
class _CountingSftpFs extends SftpFilesystem {
  _CountingSftpFs(super.store);

  int writeBytesCount = 0;

  @override
  Future<void> writeBytes(String path, List<int> bytes) {
    writeBytesCount++;
    return super.writeBytes(path, bytes);
  }
}

/// Reproduces the reported slow remote opencode launch: `WorkMachineMaterializer`
/// re-copies the entire `cli-defaults/{tool}` tree (incl. node_modules) on
/// EVERY launch, meaning the `.materialized.json` cache never hits over real
/// SSH/SFTP.
///
/// Run from `client/` (needs Docker daemon):
/// ```bash
/// flutter test test/integration/remote_materialize_cache_docker_test.dart \
///   --tags "integration && docker"
/// ```
void main() {
  DockerSshServer? server;
  SshClientFactory? sshFactory;
  SshProfile? profile;
  Directory? homeRoot;
  LocalFilesystem? homeFs;

  setUpAll(() async {
    if (!await DockerSshServer.isDockerAvailable()) {
      return;
    }
    server = await DockerSshServer.start(clientRoot: Directory.current.path);

    final credentials = InMemorySshCredentialStore();
    await credentials.savePassword(
      _profileId,
      DockerSshServer.defaultPassword,
    );
    sshFactory = SshClientFactory(
      credentialStore: credentials,
      knownHostRepository: InMemorySshKnownHostRepository(),
      onHostKeyPrompt: (_) async => true,
    );
    profile = SshProfile(
      id: _profileId,
      name: 'docker-materialize-it',
      host: server!.host,
      port: server!.port,
      username: DockerSshServer.defaultUsername,
    );

    homeRoot = await Directory.systemTemp.createTemp('tp-materialize-home-');
    homeFs = LocalFilesystem();
    await _seedHomeTree(homeFs!, homeRoot!.path);
  });

  tearDownAll(() async {
    sshFactory?.disconnectAll();
    await server?.stop();
    final root = homeRoot;
    if (root != null && await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'second reconcile over real SFTP skips unchanged files (manifest hit)',
    () async {
      if (server == null || sshFactory == null || profile == null) {
        markTestSkipped('Docker is not available');
      }
      final first = await _materialize(
        sshFactory: sshFactory!,
        profile: profile!,
        homeFs: homeFs!,
        homeRoot: homeRoot!.path,
      );
      expect(first.workFs.writeBytesCount, _homeFileCount,
          reason: 'first reconcile copies the whole tree');

      // Fresh store + fs simulates a subsequent app launch (new connection).
      final second = await _materialize(
        sshFactory: sshFactory!,
        profile: profile!,
        homeFs: homeFs!,
        homeRoot: homeRoot!.path,
      );
      expect(second.workFs.writeBytesCount, 0,
          reason: 'unchanged subtree must not be re-copied over SFTP');
      expect(
        (await second.workFs.stat(_manifestPath)).isFile,
        isTrue,
        reason: 'cache manifest must persist at <machineRoot>/.materialized.json',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

const _profileId = 'docker-materialize-it';

const _manifestPath =
    '/home/testuser/.local/share/com.hhoa.teampilot/.materialized.json';

final _homeFileCount = 600 + 3;

/// Mimics the production `cli-defaults/opencode` tree: a few config files plus
/// a large npm `node_modules` subtree (the @opencode-ai/plugin install).
Future<void> _seedHomeTree(LocalFilesystem fs, String homeRoot) async {
  final posix = p.Context(style: p.Style.posix);
  final payload = Uint8List.fromList(
    List<int>.generate(4 * 1024, (i) => (i * 7) % 256),
  );
  final dir = posix.join(
    homeRoot,
    'cli-defaults',
    'opencode',
    'node_modules',
    '@opencode-ai',
    'plugin',
    'dist',
  );
  await fs.ensureDir(dir);
  for (var i = 0; i < 600; i++) {
    await fs.writeBytes(
      posix.join(dir, 'chunk-${i.toString().padLeft(4, '0')}.js'),
      payload,
    );
  }
  await fs.writeString(
    posix.join(homeRoot, 'cli-defaults', 'opencode', 'package.json'),
    '{"dependencies":{"@opencode-ai/plugin":"0.1.0"}}',
  );
  await fs.writeString(
    posix.join(homeRoot, 'cli-defaults', 'opencode', 'package-lock.json'),
    '{"lockfileVersion":3,"packages":{}}',
  );
  await fs.writeString(
    posix.join(
      homeRoot,
      'workspace',
      'workspaces',
      'w1',
      'config',
      'opencode',
      'opencode.json',
    ),
    r'{"$schema":"https://opencode.ai/config.json"}',
  );
}

Future<({_CountingSftpFs workFs, WorkMachineMaterializer materializer})>
_materialize({
  required SshClientFactory sshFactory,
  required SshProfile profile,
  required LocalFilesystem homeFs,
  required String homeRoot,
}) async {
  final store = RemoteFileStore(
    profile: profile,
    clientFactory: sshFactory,
  );
  final workFs = _CountingSftpFs(store);
  final materializer = WorkMachineMaterializer(
    homeFs: homeFs,
    homeRoot: homeRoot,
    workFs: workFs,
    machineRoot: '/home/testuser/.local/share/com.hhoa.teampilot',
    manifest: MaterializationManifest(
      fs: workFs,
      machineRoot: '/home/testuser/.local/share/com.hhoa.teampilot',
    ),
  );
  await materializer.reconcile(tools: {'opencode'}, workspaceId: 'w1');
  return (workFs: workFs, materializer: materializer);
}

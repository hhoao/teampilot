@Tags(['integration', 'docker'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/io/sftp_filesystem.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/storage/remote_file_store.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_registry.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_transfer_service.dart';

import 'support/docker_ssh_server.dart';

/// Real Local → SFTP artifact transfer over Docker SSH.
///
/// Run from `client/` (needs Docker daemon):
/// ```bash
/// flutter test test/integration/artifact_chunked_transfer_docker_test.dart \
///   --tags "integration && docker"
/// ```
void main() {
  DockerSshServer? server;
  SshClientFactory? sshFactory;
  SshProfile? profile;
  Directory? localRoot;

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
      name: 'docker-artifact-it',
      host: server!.host,
      port: server!.port,
      username: DockerSshServer.defaultUsername,
    );
    localRoot = await Directory.systemTemp.createTemp('tp-artifact-docker-');
  });

  tearDownAll(() async {
    sshFactory?.disconnectAll();
    await server?.stop();
    final root = localRoot;
    if (root != null && await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'chunked Local→SFTP fetch delivers full payload and cleans partials',
    () async {
      if (server == null || sshFactory == null || profile == null) {
        markTestSkipped('Docker is not available');
      }
      final localFs = LocalFilesystem();
      final store = RemoteFileStore(
        profile: profile!,
        clientFactory: sshFactory!,
      );
      final remoteFs = SftpFilesystem(store);

      const remoteInbox = '/home/testuser/artifact-inbox';
      await remoteFs.ensureDir(remoteInbox);

      final sourcePath = p.join(localRoot!.path, 'payload.bin');
      // > one 4KiB chunk so the loop runs multiple times over real SFTP.
      const chunkSize = 4 * 1024;
      final bytes = List<int>.generate(chunkSize * 3 + 17, (i) => i % 256);
      await localFs.writeBytes(sourcePath, bytes);

      final service = ArtifactTransferService(
        registry: ArtifactRegistry(),
        resolveFs: (targetId) async =>
            targetId == 'local' ? localFs : remoteFs,
        targetForMember: (memberId) =>
            memberId == 'publisher' ? 'local' : 'ssh:docker',
        inboxDirFor: (memberId) =>
            memberId == 'publisher' ? localRoot!.path : remoteInbox,
        chunkSize: chunkSize,
      );

      await service.publish(
        publisherMemberId: 'publisher',
        path: sourcePath,
        name: 'payload',
      );

      final result = await service.fetch(
        fetcherMemberId: 'fetcher',
        name: 'payload',
        destPath: 'delivered.bin',
      );

      final dest = '$remoteInbox/delivered.bin';
      expect(result.finalPath, dest);
      expect(result.sizeBytes, bytes.length);
      expect(await remoteFs.readBytes(dest), bytes);
      expect((await remoteFs.stat('$dest.tp-partial')).exists, isFalse);
      expect(
        (await remoteFs.stat('$dest.tp-partial.meta.json')).exists,
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'resume continues Local→SFTP after seeded partial',
    () async {
      if (server == null || sshFactory == null || profile == null) {
        markTestSkipped('Docker is not available');
      }
      final localFs = LocalFilesystem();
      final store = RemoteFileStore(
        profile: profile!,
        clientFactory: sshFactory!,
      );
      final remoteFs = SftpFilesystem(store);

      const remoteInbox = '/home/testuser/artifact-inbox-resume';
      await remoteFs.ensureDir(remoteInbox);

      final sourcePath = p.join(localRoot!.path, 'resume.bin');
      const chunkSize = 4 * 1024;
      final bytes = List<int>.generate(chunkSize * 2 + 9, (i) => (i * 3) % 256);
      await localFs.writeBytes(sourcePath, bytes);

      final service = ArtifactTransferService(
        registry: ArtifactRegistry(),
        resolveFs: (targetId) async =>
            targetId == 'local' ? localFs : remoteFs,
        targetForMember: (memberId) =>
            memberId == 'publisher' ? 'local' : 'ssh:docker',
        inboxDirFor: (memberId) =>
            memberId == 'publisher' ? localRoot!.path : remoteInbox,
        chunkSize: chunkSize,
      );

      await service.publish(
        publisherMemberId: 'publisher',
        path: sourcePath,
        name: 'resume-payload',
      );

      final dest = '$remoteInbox/resume.bin';
      final firstChunk = bytes.sublist(0, chunkSize);
      await remoteFs.writeBytes('$dest.tp-partial', firstChunk);
      await remoteFs.writeString(
        '$dest.tp-partial.meta.json',
        '{"artifactName":"resume-payload",'
        '"publisherMemberId":"publisher",'
        '"sourceTargetId":"local",'
        '"sourcePath":${_jsonString(sourcePath)},'
        '"expectedSizeBytes":${bytes.length},'
        '"bytesWritten":$chunkSize,'
        '"chunkSize":$chunkSize}',
      );

      final result = await service.fetch(
        fetcherMemberId: 'fetcher',
        name: 'resume-payload',
        destPath: 'resume.bin',
      );

      expect(result.finalPath, dest);
      expect(await remoteFs.readBytes(dest), bytes);
      expect((await remoteFs.stat('$dest.tp-partial')).exists, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

const _profileId = 'docker-artifact-it';

String _jsonString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"');
  return '"$escaped"';
}

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/remote_target.dart';
import 'package:teampilot/models/ssh_server_profile.dart';
import 'package:teampilot/repositories/remote_target_repository.dart';
import 'package:teampilot/repositories/ssh_server_profile_repository.dart';
import 'package:teampilot/services/ssh/remote_target_sync.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late RemoteTargetRepository targetRepo;
  late SshServerProfileRepository serverRepo;
  late RemoteTargetSync sync;

  setUp(() {
    final fs = InMemoryFilesystem();
    targetRepo = RemoteTargetRepository(rootDir: '/tp', fs: fs);
    serverRepo = SshServerProfileRepository(
      storage: fakeHomeStorage(filesystem: fs),
    );
    sync = RemoteTargetSync(targets: targetRepo, servers: serverRepo);
  });

  test('push writes server profile and clears pendingSync', () async {
    await targetRepo.save(const RemoteTarget(
      id: 't1',
      name: 'dev',
      host: 'h',
      username: 'u',
      pendingSync: true,
    ));
    await sync.push((await targetRepo.findById('t1'))!);
    expect((await serverRepo.findById('t1'))!.name, 'dev');
    expect((await targetRepo.findById('t1'))!.pendingSync, isFalse);
  });

  test('pull overwrites local connection fields when remote is newer', () async {
    await targetRepo.save(const RemoteTarget(
      id: 't1',
      name: 'old',
      host: 'h',
      username: 'u',
      updatedAt: 10,
    ));
    await serverRepo.save(const SshServerProfile(
      id: 't1',
      name: 'new',
      host: 'h2',
      username: 'u',
      updatedAt: 20,
    ));
    final merged = await sync.pull((await targetRepo.findById('t1'))!);
    expect(merged.name, 'new');
    expect(merged.host, 'h2');
    expect(merged.vaultEntryId, isNull); // 凭据不动
  });

  test('pull lets newer remote nulls clear local relay fields but keeps '
      'local-only state', () async {
    await targetRepo.save(RemoteTarget(
      id: 't1',
      name: 'old',
      host: 'h',
      username: 'u',
      relayUrl: 'https://relay.example',
      pairedDesktopId: 'desktop-1',
      vaultEntryId: 'vault-1',
      hostKeyFingerprints: const ['fp-1'],
      lastHome: '/home/old',
      lastAppDataRoot: '/data/old',
      pendingSync: true,
      updatedAt: 10,
    ));
    await serverRepo.save(const SshServerProfile(
      id: 't1',
      name: 'new',
      host: 'h2',
      username: 'u',
      // relayUrl / pairedDesktopId intentionally null: a newer remote with
      // nulls must clear the stale local relay fields.
      updatedAt: 20,
    ));

    final merged = await sync.pull((await targetRepo.findById('t1'))!);

    expect(merged.name, 'new');
    expect(merged.host, 'h2');
    expect(merged.relayUrl, isNull);
    expect(merged.pairedDesktopId, isNull);
    expect(merged.vaultEntryId, 'vault-1'); // 凭据不动
    expect(merged.hostKeyFingerprints, ['fp-1']);
    expect(merged.lastHome, '/home/old');
    expect(merged.lastAppDataRoot, '/data/old');
    expect(merged.pendingSync, isTrue); // pull 不清除 pendingSync
    expect(await targetRepo.findById('t1'), merged); // 返回值即已保存值
  });
}

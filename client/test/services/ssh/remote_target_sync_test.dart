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
}

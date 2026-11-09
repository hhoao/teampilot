import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/remote_target.dart';
import 'package:teampilot/repositories/remote_target_repository.dart';
import 'package:teampilot/repositories/ssh_server_profile_repository.dart';
import 'package:teampilot/services/ssh/remote_target_sync.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  test('pull then push reconciles a pending target', () async {
    final fs = InMemoryFilesystem();
    final targets = RemoteTargetRepository(rootDir: '/tp', fs: fs);
    final servers = SshServerProfileRepository(
      storage: fakeHomeStorage(filesystem: fs),
    );
    final sync = RemoteTargetSync(targets: targets, servers: servers);

    await targets.save(
      const RemoteTarget(
        id: 't1',
        name: 'dev',
        host: 'h',
        username: 'u',
        pendingSync: true,
        updatedAt: 10,
      ),
    );

    final merged = await sync.pull((await targets.findById('t1'))!);
    await sync.push(merged);

    expect((await servers.findById('t1'))!.name, 'dev');
    expect((await targets.findById('t1'))!.pendingSync, isFalse);
  });
}

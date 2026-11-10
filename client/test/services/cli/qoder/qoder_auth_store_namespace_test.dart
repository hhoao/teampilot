import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/qoder/provider/qoder_auth_store.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  test('namespace moves login and provider stores under its own root', () {
    final store = QoderAuthStore(
      fs: fs,
      basePath: '/app',
      pathContext: p.posix,
      machineHome: '/home/me',
      namespace: 'qoder-cn',
    );

    expect(store.loginRoot('work'), '/app/cli-login/qoder-cn/work');
    expect(store.loginConfigDir('work'), '/app/cli-login/qoder-cn/work/config');
    expect(store.providerAuthDir('work'), '/app/providers/qoder-cn/work');
  });

  test(
    'disabled machine fallback ignores an existing ~/.qoder login',
    () async {
      await fs.ensureDir('/home/me/.qoder/.auth');
      await fs.atomicWrite('/home/me/.qoder/.auth/user', 'MACHINE');
      await fs.atomicWrite('/home/me/.qoder/.auth/machine_id', 'MID');

      final store = QoderAuthStore(
        fs: fs,
        basePath: '/app',
        pathContext: p.posix,
        machineHome: '/home/me',
        namespace: 'qoder-cn',
        useMachineFallback: false,
      );

      expect(await store.authSourceDir('work'), isNull);
      expect(
        await store.seedSessionAuth(
          providerId: 'work',
          sessionConfigDir: '/sessions/s1/qoder-cn',
        ),
        isFalse,
      );
      expect((await fs.stat('/sessions/s1/qoder-cn/.auth')).exists, isFalse);
    },
  );

  test('enabled fallback keeps the existing global behavior', () async {
    await fs.ensureDir('/home/me/.qoder/.auth');
    await fs.atomicWrite('/home/me/.qoder/.auth/user', 'MACHINE');
    await fs.atomicWrite('/home/me/.qoder/.auth/machine_id', 'MID');

    final store = QoderAuthStore(
      fs: fs,
      basePath: '/app',
      pathContext: p.posix,
      machineHome: '/home/me',
    );

    expect(await store.authSourceDir('work'), '/home/me/.qoder/.auth');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/qoder/provider/qoder_auth_store.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late QoderAuthStore store;

  setUp(() {
    fs = InMemoryFilesystem();
    store = QoderAuthStore(
      fs: fs,
      basePath: '/app',
      pathContext: p.posix,
      machineHome: '/home/me',
      namespace: 'qoder-cn',
      useMachineFallback: false,
    );
  });

  test('login and provider roots use the qoder-cn namespace', () {
    expect(store.loginRoot('work'), '/app/cli-login/qoder-cn/work');
    expect(store.providerAuthDir('work'), '/app/providers/qoder-cn/work');
  });

  test('never reads the machine ~/.qoder login', () async {
    await fs.ensureDir('/home/me/.qoder/.auth');
    await fs.atomicWrite('/home/me/.qoder/.auth/user', 'MACHINE');
    await fs.atomicWrite('/home/me/.qoder/.auth/machine_id', 'MID');

    expect(await store.authSourceDir('work'), isNull);
    expect(
      await store.seedSessionAuth(
        providerId: 'work',
        sessionConfigDir: '/sessions/s1/qoder-cn',
      ),
      isFalse,
    );
    expect((await fs.stat('/sessions/s1/qoder-cn/.auth')).exists, isFalse);
  });

  test('seeds from the CN provider store only', () async {
    await store.fs.ensureDir(store.providerAuthDir('work'));
    await store.fs.atomicWrite('${store.providerAuthDir('work')}/user', 'CN');
    await store.fs.atomicWrite(
      '${store.providerAuthDir('work')}/machine_id',
      'CNMID',
    );

    expect(
      await store.seedSessionAuth(
        providerId: 'work',
        sessionConfigDir: '/sessions/s1/qoder-cn',
      ),
      isTrue,
    );
    expect(await fs.readString('/sessions/s1/qoder-cn/.auth/user'), 'CN');
  });
}

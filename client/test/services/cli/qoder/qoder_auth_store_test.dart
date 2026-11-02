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
    );
  });

  test('copies login user + machine_id into the provider store', () async {
    final loginConfig = store.loginConfigDir('work');
    await fs.ensureDir('$loginConfig/.auth');
    await fs.atomicWrite('$loginConfig/.auth/user', 'USER');
    await fs.atomicWrite('$loginConfig/.auth/machine_id', 'MID');

    expect(
      await store.writeProviderAuthFromLogin('work', loginConfigDir: loginConfig),
      isTrue,
    );
    expect(await store.hasProviderAuth('work'), isTrue);
    expect(await fs.readString('${store.providerAuthDir('work')}/user'), 'USER');
    expect(
      await fs.readString('${store.providerAuthDir('work')}/machine_id'),
      'MID',
    );
  });

  test('seeds a session config dir from the provider store', () async {
    final loginConfig = store.loginConfigDir('work');
    await fs.ensureDir('$loginConfig/.auth');
    await fs.atomicWrite('$loginConfig/.auth/user', 'USER');
    await fs.atomicWrite('$loginConfig/.auth/machine_id', 'MID');
    await store.writeProviderAuthFromLogin('work', loginConfigDir: loginConfig);

    expect(
      await store.seedSessionAuth(
        providerId: 'work',
        sessionConfigDir: '/sessions/s1/qoder',
      ),
      isTrue,
    );
    expect(await fs.readString('/sessions/s1/qoder/.auth/user'), 'USER');
  });

  test('falls back to the machine ~/.qoder auth when no provider exists', () async {
    await fs.ensureDir('/home/me/.qoder/.auth');
    await fs.atomicWrite('/home/me/.qoder/.auth/user', 'MACHINE');
    await fs.atomicWrite('/home/me/.qoder/.auth/machine_id', 'M2');

    expect(
      await store.seedSessionAuth(
        providerId: 'missing',
        sessionConfigDir: '/sessions/s1/qoder',
      ),
      isTrue,
    );
    expect(await fs.readString('/sessions/s1/qoder/.auth/user'), 'MACHINE');
  });
}

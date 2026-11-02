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
      await store.writeProviderAuthFromLogin(
        'work',
        loginConfigDir: loginConfig,
      ),
      isTrue,
    );
    expect(await store.hasProviderAuth('work'), isTrue);
    expect(
      await fs.readString('${store.providerAuthDir('work')}/user'),
      'USER',
    );
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

  test(
    'falls back to the machine ~/.qoder auth when no provider exists',
    () async {
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
    },
  );

  test(
    'login copy fails and writes nothing when machine_id is missing',
    () async {
      final loginConfig = store.loginConfigDir('work');
      await fs.ensureDir('$loginConfig/.auth');
      await fs.atomicWrite('$loginConfig/.auth/user', 'USER');

      expect(
        await store.writeProviderAuthFromLogin(
          'work',
          loginConfigDir: loginConfig,
        ),
        isFalse,
      );
      expect(await store.hasProviderAuth('work'), isFalse);
      expect(
        (await fs.stat(store.providerAuthDir('work'))).exists,
        isFalse,
        reason: 'a partial login must not create a half-filled provider row',
      );
    },
  );

  test(
    'seeding fails when neither the provider nor the machine has auth',
    () async {
      expect(
        await store.seedSessionAuth(
          providerId: 'missing',
          sessionConfigDir: '/sessions/s1/qoder',
        ),
        isFalse,
      );
      expect(
        (await fs.stat('/sessions/s1/qoder/.auth')).exists,
        isFalse,
        reason: 'no source means no target directory either',
      );
    },
  );

  test('provider auth wins over a machine ~/.qoder login', () async {
    final loginConfig = store.loginConfigDir('work');
    await fs.ensureDir('$loginConfig/.auth');
    await fs.atomicWrite('$loginConfig/.auth/user', 'USER');
    await fs.atomicWrite('$loginConfig/.auth/machine_id', 'MID');
    await store.writeProviderAuthFromLogin('work', loginConfigDir: loginConfig);

    await fs.ensureDir('/home/me/.qoder/.auth');
    await fs.atomicWrite('/home/me/.qoder/.auth/user', 'MACHINE');
    await fs.atomicWrite('/home/me/.qoder/.auth/machine_id', 'M2');

    expect(
      await store.seedSessionAuth(
        providerId: 'work',
        sessionConfigDir: '/sessions/s1/qoder',
      ),
      isTrue,
    );
    expect(await fs.readString('/sessions/s1/qoder/.auth/user'), 'USER');
    expect(await fs.readString('/sessions/s1/qoder/.auth/machine_id'), 'MID');
  });

  test(
    'a partial provider row does not fall back to the machine copy',
    () async {
      final providerDir = store.providerAuthDir('work');
      await fs.ensureDir(providerDir);
      await fs.atomicWrite('$providerDir/user', 'PARTIAL');

      await fs.ensureDir('/home/me/.qoder/.auth');
      await fs.atomicWrite('/home/me/.qoder/.auth/user', 'MACHINE');
      await fs.atomicWrite('/home/me/.qoder/.auth/machine_id', 'M2');

      expect(
        await store.seedSessionAuth(
          providerId: 'work',
          sessionConfigDir: '/sessions/s1/qoder',
        ),
        isFalse,
      );
      expect(
        await fs.readString('/sessions/s1/qoder/.auth/user'),
        isNull,
        reason: 'a broken provider row must never switch the account silently',
      );
    },
  );

  test('seeding fails when the plane home is unknown', () async {
    // An empty home must not resolve `.qoder/.auth` relative to the cwd.
    await fs.ensureDir('.qoder/.auth');
    await fs.atomicWrite('.qoder/.auth/user', 'RELATIVE');
    await fs.atomicWrite('.qoder/.auth/machine_id', 'R1');
    final homless = QoderAuthStore(
      fs: fs,
      basePath: '/app',
      pathContext: p.posix,
      machineHome: '',
    );

    expect(
      await homless.seedSessionAuth(
        providerId: 'missing',
        sessionConfigDir: '/sessions/s1/qoder',
      ),
      isFalse,
    );
    expect((await fs.stat('/sessions/s1/qoder/.auth')).exists, isFalse);
  });

  test(
    'keeps an already seeded session .auth instead of clobbering it',
    () async {
      final loginConfig = store.loginConfigDir('work');
      await fs.ensureDir('$loginConfig/.auth');
      await fs.atomicWrite('$loginConfig/.auth/user', 'OLD');
      await fs.atomicWrite('$loginConfig/.auth/machine_id', 'OLD_MID');
      await store.writeProviderAuthFromLogin(
        'work',
        loginConfigDir: loginConfig,
      );
      expect(
        await store.seedSessionAuth(
          providerId: 'work',
          sessionConfigDir: '/sessions/s1/qoder',
        ),
        isTrue,
      );
      expect(
        await fs.readString('/sessions/s1/qoder/.auth/.qoder-provider'),
        'work',
      );

      // The session refreshed its own copy after materialization.
      await fs.atomicWrite('/sessions/s1/qoder/.auth/user', 'REFRESHED');
      await fs.atomicWrite('$loginConfig/.auth/user', 'NEW');
      expect(
        await store.seedSessionAuth(
          providerId: 'work',
          sessionConfigDir: '/sessions/s1/qoder',
        ),
        isTrue,
      );
      expect(await fs.readString('/sessions/s1/qoder/.auth/user'), 'REFRESHED');
    },
  );

  test('reseed the session when the provider marker changes', () async {
    Future<void> seedProvider(String providerId, String user) async {
      final loginConfig = store.loginConfigDir(providerId);
      await fs.ensureDir('$loginConfig/.auth');
      await fs.atomicWrite('$loginConfig/.auth/user', user);
      await fs.atomicWrite('$loginConfig/.auth/machine_id', '${user}_MID');
      await store.writeProviderAuthFromLogin(
        providerId,
        loginConfigDir: loginConfig,
      );
    }

    await seedProvider('work', 'WORK');
    await seedProvider('personal', 'PERSONAL');
    expect(
      await store.seedSessionAuth(
        providerId: 'work',
        sessionConfigDir: '/sessions/s1/qoder',
      ),
      isTrue,
    );
    expect(await fs.readString('/sessions/s1/qoder/.auth/user'), 'WORK');

    // The seat switched accounts: the marker no longer matches, so the new
    // provider's credentials replace the old copy.
    expect(
      await store.seedSessionAuth(
        providerId: 'personal',
        sessionConfigDir: '/sessions/s1/qoder',
      ),
      isTrue,
    );
    expect(await fs.readString('/sessions/s1/qoder/.auth/user'), 'PERSONAL');
    expect(
      await fs.readString('/sessions/s1/qoder/.auth/machine_id'),
      'PERSONAL_MID',
    );
    expect(
      await fs.readString('/sessions/s1/qoder/.auth/.qoder-provider'),
      'personal',
    );
  });

  test('records the machine marker for the fallback seed', () async {
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
    expect(
      await fs.readString('/sessions/s1/qoder/.auth/.qoder-provider'),
      QoderAuthStore.machineMarkerValue,
    );
  });

  test('keeps a legacy session copy when the marker is missing', () async {
    await fs.ensureDir('/sessions/s1/qoder/.auth');
    await fs.atomicWrite('/sessions/s1/qoder/.auth/user', 'LEGACY');
    await fs.atomicWrite('/sessions/s1/qoder/.auth/machine_id', 'L1');

    final loginConfig = store.loginConfigDir('work');
    await fs.ensureDir('$loginConfig/.auth');
    await fs.atomicWrite('$loginConfig/.auth/user', 'WORK');
    await fs.atomicWrite('$loginConfig/.auth/machine_id', 'WORK_MID');
    await store.writeProviderAuthFromLogin('work', loginConfigDir: loginConfig);

    expect(
      await store.seedSessionAuth(
        providerId: 'work',
        sessionConfigDir: '/sessions/s1/qoder',
      ),
      isTrue,
    );
    expect(
      await fs.readString('/sessions/s1/qoder/.auth/user'),
      'LEGACY',
      reason: 'a preexisting session without a marker is never clobbered',
    );
  });

  test('authSourceDir resolves the provider store, then the machine', () async {
    expect(await store.authSourceDir('work'), isNull);

    await fs.ensureDir('/home/me/.qoder/.auth');
    await fs.atomicWrite('/home/me/.qoder/.auth/user', 'MACHINE');
    await fs.atomicWrite('/home/me/.qoder/.auth/machine_id', 'M2');
    expect(await store.authSourceDir('work'), '/home/me/.qoder/.auth');

    final providerDir = store.providerAuthDir('work');
    await fs.ensureDir(providerDir);
    await fs.atomicWrite('$providerDir/user', 'WORK');
    await fs.atomicWrite('$providerDir/machine_id', 'W1');
    expect(await store.authSourceDir('work'), providerDir);

    await fs.removeRecursive('$providerDir/machine_id');
    expect(
      await store.authSourceDir('work'),
      isNull,
      reason: 'a partial provider row never falls back to the machine login',
    );
  });

  test('truncated or dotted provider ids cannot escape the provider root', () {
    expect(store.providerAuthDir('..'), '/app/providers/qoder/provider');
    expect(store.providerAuthDir('.'), '/app/providers/qoder/provider');
    expect(store.providerAuthDir(''), '/app/providers/qoder/provider');
  });
}

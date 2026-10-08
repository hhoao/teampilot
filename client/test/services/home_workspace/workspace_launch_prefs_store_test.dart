import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/home_workspace/landing_prefs_store.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  test('round-trips per-workspace landing prefs', () async {
    final fs = InMemoryFilesystem();
    final store = LandingPrefsStore(
      fs: fs,
      pathOverride: '/prefs.json',
      storage: fakeHomeStorage(filesystem: fs),
    );

    await store.save(
      'ws-a',
      const LandingPrefs(
        isPersonal: false,
        teamId: 'team-1',
        workingDirectoryPath: '/projects/app',
      ),
    );

    final loaded = await store.prefsFor('ws-a');
    expect(loaded?.isPersonal, isFalse);
    expect(loaded?.teamId, 'team-1');
    expect(loaded?.workingDirectoryPath, '/projects/app');
  });

  test('generate launch survives prefs round trip in team mode', () async {
    final fs = InMemoryFilesystem();
    final store = LandingPrefsStore(
      fs: fs,
      pathOverride: '/prefs.json',
      storage: fakeHomeStorage(filesystem: fs),
    );
    await store.save(
      'workspace-1',
      const LandingPrefs(
        isPersonal: false,
        generateLaunch: true,
        teamId: 'last-team',
      ),
    );
    final loaded = await store.prefsFor('workspace-1');
    expect(loaded?.generateLaunch, isTrue);
    expect(loaded?.teamId, 'last-team');
  });

  test('old JSON without generateLaunch defaults to false', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      '/prefs.json',
      '{"ws-old":{"isPersonal":false,"teamId":"team-1"}}',
    );
    final store = LandingPrefsStore(
      fs: fs,
      pathOverride: '/prefs.json',
      storage: fakeHomeStorage(filesystem: fs),
    );

    final loaded = await store.prefsFor('ws-old');
    expect(loaded?.generateLaunch, isFalse);
  });

  test('saved landing preferences omit launch security policy', () async {
    final fs = InMemoryFilesystem();
    final store = LandingPrefsStore(
      fs: fs,
      pathOverride: '/prefs.json',
      storage: fakeHomeStorage(filesystem: fs),
    );

    await store.save('ws-a', const LandingPrefs());

    final raw = await fs.readString('/prefs.json');
    expect(raw, isNot(contains('"launchSecurityPolicy"')));
    expect(raw, isNot(contains('dangerouslySkipPermissions')));
  });
}

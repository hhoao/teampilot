import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/home_workspace/landing_prefs_store.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  test('LandingPrefs defaults dangerouslySkipPermissions to true', () {
    expect(const LandingPrefs().dangerouslySkipPermissions, isTrue);
  });

  test('round-trips per-workspace landing prefs', () async {
    final fs = InMemoryFilesystem();
    final store = LandingPrefsStore(fs: fs, pathOverride: '/prefs.json');

    await store.save(
      'ws-a',
      const LandingPrefs(
        isPersonal: false,
        teamId: 'team-1',
        workingDirectoryPath: '/projects/app',
        dangerouslySkipPermissions: true,
      ),
    );

    final loaded = await store.prefsFor('ws-a');
    expect(loaded?.isPersonal, isFalse);
    expect(loaded?.teamId, 'team-1');
    expect(loaded?.workingDirectoryPath, '/projects/app');
    expect(loaded?.dangerouslySkipPermissions, isTrue);
  });

  test('always persists dangerouslySkipPermissions false', () async {
    final fs = InMemoryFilesystem();
    final store = LandingPrefsStore(fs: fs, pathOverride: '/prefs.json');

    await store.save(
      'ws-a',
      const LandingPrefs(dangerouslySkipPermissions: false),
    );

    final raw = await fs.readString('/prefs.json');
    expect(raw, contains('"dangerouslySkipPermissions":false'));

    final loaded = await store.prefsFor('ws-a');
    expect(loaded?.dangerouslySkipPermissions, isFalse);
  });

  test('missing dangerouslySkipPermissions key loads as true', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      '/prefs.json',
      '{"ws-a":{"isPersonal":true}}',
    );
    final store = LandingPrefsStore(fs: fs, pathOverride: '/prefs.json');

    final loaded = await store.prefsFor('ws-a');
    expect(loaded?.dangerouslySkipPermissions, isTrue);
  });
}

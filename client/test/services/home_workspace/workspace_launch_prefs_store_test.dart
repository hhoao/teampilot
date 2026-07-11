import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/home_workspace/landing_prefs_store.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
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
}

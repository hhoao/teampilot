import 'package:teampilot/models/launch_security_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/home_workspace/landing_prefs_store.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  test('LandingPrefs defaults to full access for landing compatibility', () {
    expect(
      const LandingPrefs().launchSecurityPolicy.requiresDangerousExecution,
      isTrue,
    );
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
        launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
      ),
    );

    final loaded = await store.prefsFor('ws-a');
    expect(loaded?.isPersonal, isFalse);
    expect(loaded?.teamId, 'team-1');
    expect(loaded?.workingDirectoryPath, '/projects/app');
    expect(loaded?.launchSecurityPolicy.requiresDangerousExecution, isTrue);
  });

  test('persists the normalized launch security policy object', () async {
    final fs = InMemoryFilesystem();
    final store = LandingPrefsStore(fs: fs, pathOverride: '/prefs.json');

    await store.save(
      'ws-a',
      const LandingPrefs(launchSecurityPolicy: LaunchSecurityPolicy.cliDefault),
    );

    final raw = await fs.readString('/prefs.json');
    expect(raw, contains('"launchSecurityPolicy"'));
    expect(raw, isNot(contains('dangerouslySkipPermissions')));

    final loaded = await store.prefsFor('ws-a');
    expect(loaded?.launchSecurityPolicy.requiresDangerousExecution, isFalse);
  });

  test(
    'missing launch security policy loads the full-access application default',
    () async {
      final fs = InMemoryFilesystem();
      await fs.writeString('/prefs.json', '{"ws-a":{"isPersonal":true}}');
      final store = LandingPrefsStore(fs: fs, pathOverride: '/prefs.json');

      final loaded = await store.prefsFor('ws-a');
      expect(loaded?.launchSecurityPolicy.requiresDangerousExecution, isTrue);
    },
  );
}

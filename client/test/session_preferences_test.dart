import 'package:flashskyai_client/models/session_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionPreferences', () {
    test('defaults are empty path and auto-launch off', () {
      const prefs = SessionPreferences();
      expect(prefs.cliExecutablePath, '');
      expect(prefs.autoLaunchAllMembersOnConnect, false);
      expect(prefs.scopeSessionsToSelectedTeam, false);
    });

    test('toJson/fromJson round-trips', () {
      const prefs = SessionPreferences(
        cliExecutablePath: '/opt/bin/flashskyai',
        autoLaunchAllMembersOnConnect: true,
        scopeSessionsToSelectedTeam: true,
      );
      final restored = SessionPreferences.fromJson(prefs.toJson());
      expect(restored.cliExecutablePath, '/opt/bin/flashskyai');
      expect(restored.autoLaunchAllMembersOnConnect, true);
      expect(restored.scopeSessionsToSelectedTeam, true);
    });

    test('fromJson falls back to defaults when keys are missing', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{});
      expect(restored.cliExecutablePath, '');
      expect(restored.autoLaunchAllMembersOnConnect, false);
      expect(restored.scopeSessionsToSelectedTeam, false);
    });

    test('copyWith updates only specified fields', () {
      const prefs = SessionPreferences();
      final next = prefs.copyWith(cliExecutablePath: '/a/b');
      expect(next.cliExecutablePath, '/a/b');
      expect(next.autoLaunchAllMembersOnConnect, false);
      expect(next.scopeSessionsToSelectedTeam, false);
      final next2 = prefs.copyWith(scopeSessionsToSelectedTeam: true);
      expect(next2.scopeSessionsToSelectedTeam, true);
      expect(next2.cliExecutablePath, '');
    });
  });
}

import 'package:teampilot/models/session_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionPreferences', () {
    test('defaults are empty path with session scoping on', () {
      const prefs = SessionPreferences();
      expect(prefs.cliExecutablePath, '');
      expect(prefs.autoLaunchAllMembersOnConnect, true);
      expect(prefs.scopeSessionsToSelectedTeam, true);
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
      expect(restored.autoLaunchAllMembersOnConnect, true);
      expect(restored.scopeSessionsToSelectedTeam, true);
    });

    test('copyWith updates only specified fields', () {
      const prefs = SessionPreferences();
      final next = prefs.copyWith(cliExecutablePath: '/a/b');
      expect(next.cliExecutablePath, '/a/b');
      expect(next.autoLaunchAllMembersOnConnect, true);
      expect(next.scopeSessionsToSelectedTeam, true);
      final next2 = prefs.copyWith(scopeSessionsToSelectedTeam: true);
      expect(next2.scopeSessionsToSelectedTeam, true);
      expect(next2.cliExecutablePath, '');
    });
  });
}

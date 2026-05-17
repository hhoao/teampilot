import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/connection_mode.dart';
import 'package:teampilot/models/session_preferences.dart';

void main() {
  group('SessionPreferences', () {
    test('defaults are empty path with session scoping on', () {
      final prefs = SessionPreferences();
      expect(prefs.cliExecutablePath, '');
      expect(prefs.defaultSshWorkingDirectory, '');
      expect(prefs.sshUseLoginShell, false);
      expect(prefs.autoLaunchAllMembersOnConnect, true);
      expect(prefs.scopeSessionsToSelectedTeam, true);
    });

    test('toJson/fromJson round-trips', () {
      final prefs = SessionPreferences(
        connectionMode: ConnectionMode.ssh,
        cliExecutablePath: '/opt/bin/flashskyai',
        defaultSshWorkingDirectory: '~/work',
        sshUseLoginShell: true,
        autoLaunchAllMembersOnConnect: true,
        scopeSessionsToSelectedTeam: true,
      );
      final restored = SessionPreferences.fromJson(prefs.toJson());
      expect(restored.connectionMode, ConnectionMode.ssh);
      expect(restored.cliExecutablePath, '/opt/bin/flashskyai');
      expect(restored.defaultSshWorkingDirectory, '~/work');
      expect(restored.sshUseLoginShell, true);
      expect(restored.autoLaunchAllMembersOnConnect, true);
      expect(restored.scopeSessionsToSelectedTeam, true);
    });

    test('fromJson falls back to defaults when keys are missing', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{});
      expect(restored.cliExecutablePath, '');
      expect(restored.defaultSshWorkingDirectory, '');
      expect(restored.sshUseLoginShell, false);
      expect(restored.autoLaunchAllMembersOnConnect, true);
      expect(restored.scopeSessionsToSelectedTeam, true);
    });

    test('copyWith updates only specified fields', () {
      final prefs = SessionPreferences();
      final next = prefs.copyWith(cliExecutablePath: '/a/b');
      expect(next.cliExecutablePath, '/a/b');
      expect(next.defaultSshWorkingDirectory, '');
      expect(next.sshUseLoginShell, false);
      expect(next.autoLaunchAllMembersOnConnect, true);
      expect(next.scopeSessionsToSelectedTeam, true);
      final next2 = prefs.copyWith(scopeSessionsToSelectedTeam: true);
      expect(next2.scopeSessionsToSelectedTeam, true);
      expect(next2.cliExecutablePath, '');
    });
  });
}

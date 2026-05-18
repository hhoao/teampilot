import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/models/connection_mode.dart';

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
        cliExecutablePaths: const {
          'claude': '/opt/bin/claude',
          'codex': '/opt/bin/codex',
        },
        defaultSshWorkingDirectory: '~/work',
        sshUseLoginShell: true,
        autoLaunchAllMembersOnConnect: true,
        scopeSessionsToSelectedTeam: true,
      );
      final restored = SessionPreferences.fromJson(prefs.toJson());
      expect(restored.connectionMode, ConnectionMode.ssh);
      expect(restored.cliExecutablePath, '/opt/bin/flashskyai');
      expect(restored.cliExecutablePaths, {
        'claude': '/opt/bin/claude',
        'codex': '/opt/bin/codex',
      });
      expect(restored.defaultSshWorkingDirectory, '~/work');
      expect(restored.sshUseLoginShell, true);
      expect(restored.autoLaunchAllMembersOnConnect, true);
      expect(restored.scopeSessionsToSelectedTeam, true);
    });

    test('fromJson falls back to defaults when keys are missing', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{});
      expect(restored.cliExecutablePath, '');
      expect(restored.cliExecutablePaths, isEmpty);
      expect(restored.defaultSshWorkingDirectory, '');
      expect(restored.sshUseLoginShell, false);
      expect(restored.autoLaunchAllMembersOnConnect, true);
      expect(restored.scopeSessionsToSelectedTeam, true);
    });

    test('copyWith updates only specified fields', () {
      final prefs = SessionPreferences();
      final next = prefs.copyWith(
        cliExecutablePath: '/a/b',
        cliExecutablePaths: const {'claude': '/c/d'},
      );
      expect(next.cliExecutablePath, '/a/b');
      expect(next.cliExecutablePaths, {'claude': '/c/d'});
      expect(next.defaultSshWorkingDirectory, '');
      expect(next.sshUseLoginShell, false);
      expect(next.autoLaunchAllMembersOnConnect, true);
      expect(next.scopeSessionsToSelectedTeam, true);
      final next2 = prefs.copyWith(scopeSessionsToSelectedTeam: true);
      expect(next2.scopeSessionsToSelectedTeam, true);
      expect(next2.cliExecutablePath, '');
      expect(next2.cliExecutablePaths, isEmpty);
    });

    test('fromJson ignores non-string cli executable path entries', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{
        'cliExecutablePaths': {
          'claude': '/opt/bin/claude',
          'codex': 42,
          '': '/bad',
          'flashskyai': '   ',
        },
      });

      expect(restored.cliExecutablePaths, {'claude': '/opt/bin/claude'});
    });
  });
}

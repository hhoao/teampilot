import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/models/connection_mode.dart';
import 'package:teampilot/models/windows_storage_backend.dart';

void main() {
  group('SessionPreferences', () {
    test('defaults are empty path with session scoping on', () {
      final prefs = SessionPreferences();
      expect(prefs.cliExecutablePathFor('flashskyai'), '');
      expect(prefs.defaultSshWorkingDirectory, '');
      expect(prefs.sshUseLoginShell, false);
      expect(prefs.autoLaunchAllMembersOnConnect, true);
      expect(prefs.scopeSessionsToSelectedTeam, true);
      expect(prefs.windowsStorageBackend, WindowsStorageBackend.native);
    });

    test('toJson/fromJson round-trips', () {
      final prefs = SessionPreferences(
        connectionMode: ConnectionMode.ssh,
        cliExecutablePaths: const {
          'flashskyai': '/opt/bin/flashskyai',
          'claude': '/opt/bin/claude',
          'codex': '/opt/bin/codex',
        },
        defaultSshWorkingDirectory: '~/work',
        sshUseLoginShell: true,
        autoLaunchAllMembersOnConnect: true,
        scopeSessionsToSelectedTeam: true,
        windowsStorageBackend: WindowsStorageBackend.wsl,
      );
      final restored = SessionPreferences.fromJson(prefs.toJson());
      expect(restored.connectionMode, ConnectionMode.ssh);
      expect(restored.cliExecutablePaths, {
        'flashskyai': '/opt/bin/flashskyai',
        'claude': '/opt/bin/claude',
        'codex': '/opt/bin/codex',
      });
      expect(restored.defaultSshWorkingDirectory, '~/work');
      expect(restored.sshUseLoginShell, true);
      expect(restored.autoLaunchAllMembersOnConnect, true);
      expect(restored.scopeSessionsToSelectedTeam, true);
      expect(restored.windowsStorageBackend, WindowsStorageBackend.wsl);
    });

    test('fromJson falls back to defaults when keys are missing', () {
      final restored = SessionPreferences.fromJson(const <String, Object?>{});
      expect(restored.cliExecutablePaths, isEmpty);
      expect(restored.defaultSshWorkingDirectory, '');
      expect(restored.sshUseLoginShell, false);
      expect(restored.autoLaunchAllMembersOnConnect, true);
      expect(restored.scopeSessionsToSelectedTeam, true);
      expect(restored.windowsStorageBackend, WindowsStorageBackend.native);
    });

    test('copyWith updates only specified fields', () {
      final prefs = SessionPreferences();
      final next = prefs.copyWith(
        cliExecutablePaths: const {
          'flashskyai': '/a/b',
          'claude': '/c/d',
        },
      );
      expect(next.cliExecutablePathFor('flashskyai'), '/a/b');
      expect(next.cliExecutablePaths, {
        'flashskyai': '/a/b',
        'claude': '/c/d',
      });
      expect(next.defaultSshWorkingDirectory, '');
      expect(next.sshUseLoginShell, false);
      expect(next.autoLaunchAllMembersOnConnect, true);
      expect(next.scopeSessionsToSelectedTeam, true);
      final next2 = prefs.copyWith(scopeSessionsToSelectedTeam: true);
      expect(next2.scopeSessionsToSelectedTeam, true);
      expect(next2.cliExecutablePaths, isEmpty);
    });

    test('copyWith updates windowsStorageBackend', () {
      final prefs = SessionPreferences();
      final next = prefs.copyWith(windowsStorageBackend: WindowsStorageBackend.wsl);
      expect(next.windowsStorageBackend, WindowsStorageBackend.wsl);
      expect(prefs.windowsStorageBackend, WindowsStorageBackend.native);
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
